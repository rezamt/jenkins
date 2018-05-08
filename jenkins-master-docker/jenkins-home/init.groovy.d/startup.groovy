import hudson.model.*
import hudson.plugins.gradle.*
import hudson.tools.*
import hudson.security.*
import jenkins.model.*
import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration

import org.jenkinsci.plugins.saml.IdpMetadataConfiguration
import org.jenkinsci.plugins.saml.SamlAdvancedConfiguration
import org.jenkinsci.plugins.saml.SamlAdvancedConfiguration
import org.jenkinsci.plugins.saml.SamlEncryptionData
import org.jenkinsci.plugins.saml.SamlSecurityRealm


import com.amazonaws.ClientConfiguration
import com.amazonaws.regions.RegionUtils
import com.amazonaws.services.ecs.AmazonECSClient
import com.amazonaws.util.EC2MetadataUtils
import com.amazonaws.services.elasticloadbalancing.*
import com.amazonaws.services.elasticloadbalancing.model.*
import com.cloudbees.jenkins.plugins.amazonecs.ECSCloud
import com.cloudbees.jenkins.plugins.amazonecs.ECSTaskTemplate


import java.util.logging.Logger


class JenkinsConfigurator {

    def JENKINS_HOME = Jenkins.get().getRootDir().absolutePath

    def JENKINS_PROPERTY = "jenkins.properties"

    def props = new Properties()

    def initJenkinsProperties() {
        File propertiesFile = new File("${JENKINS_HOME}/init.groovy.d/${JENKINS_PROPERTY}")
        props = new Properties()

        if (propertiesFile.exists()) {
            Logger.global.info("Loading system properties from ${propertiesFile.absolutePath}")

            propertiesFile.withReader { r ->
                props.load(r)
            }
        }
    }


    def configureJenkinsURL() {
        String jenkinsURL = queryJenkinsURL()
        Logger.global.info("Set Jenkins URL to $jenkinsURL")
        def config = JenkinsLocationConfiguration.get()
        config.url = jenkinsURL
        config.save()
    }

    String queryJenkinsURL() {
        //assume default port 80
        "http://${queryElbDNSName()}/"
    }

    String queryElbDNSName() {
        AmazonElasticLoadBalancingClient client = new AmazonElasticLoadBalancingClient(clientConfiguration);
        client.setRegion(RegionUtils.getRegion(region))
        DescribeLoadBalancersRequest request = new DescribeLoadBalancersRequest()
                .withLoadBalancerNames('jenkins-elb');
        DescribeLoadBalancersResult result = client.describeLoadBalancers(request);
        result.loadBalancerDescriptions.first().DNSName
    }


    def buildJob(String jobName, def params = null) {
        Logger.global.info("Building job '$jobName")
        def job = Jenkins.get().getJob(jobName)
        Jenkins.get().queue.schedule(job, 0, new CauseAction(new Cause() {
            @Override
            String getShortDescription() {
                'Jenkins startup script'
            }
        }), params)
    }

    def getClientConfiguration() {
        new ClientConfiguration()
    }

    String getRegion() {
        EC2MetadataUtils.instanceInfo.region
    }

    String queryJenkinsClusterArn(String regionName) {
        AmazonECSClient client = new AmazonECSClient(clientConfiguration)
        client.setRegion(RegionUtils.getRegion(regionName))
        client.listClusters().getClusterArns().find { it.endsWith('jenkins-cluster') }
    }

    def configureSecuritySettings() {

        Logger.global.info("[Config] Configuring Security Setting ")

        def IDPFilePath = "${JENKINS_HOME}/${props.IDP_METADATA_FILE_NAME}"

        Logger.global.info("Checking for SAML configuration: ${IDPFilePath}")

        def idpMetadataFile = new File(IDPFilePath)
        def xmlMetaData = ""
        if (!idpMetadataFile.exists()) {
            Logger.global.warning("IDP Metadata file doesn't exist.")
            idpMetadataFile.createNewFile()
        } else {
            Logger.global.info("Reading IDP Metadata configuration ...")
            xmlMetaData = idpMetadataFile.getText()
        }

        def urlMetaData = props.urlMetaData

        Integer period = new Integer(props.idpMetaDataRefreshPeriod)
        IdpMetadataConfiguration idpMetadataConfiguration = new IdpMetadataConfiguration(xmlMetaData, urlMetaData, period)

        def displayNameAttributeName = props.displayNameAttributeName
        def groupsAttributeName = props.groupsAttributeName
        def usernameAttributeName = props.usernameAttributeName
        def emailAttributeName = props.emailAttributeName
        def maximumAuthenticationLifetime = new Integer(props.maximumAuthenticationLifetime)
        def logoutUrl = props.logoutUrl


        def forceAuthn = Boolean.parseBoolean(props.forceAuthn)

        // Whether to request the SAML IdP to force (re)authentication of the user, rather than allowing an existing session with the IdP to be reused. Off by default.
        def authnContextClassRef = ""
        // If this field is not empty, request that the SAML IdP uses a specific authentication context, rather than its default. Check with the IdP administrators to find out which authentication contexts are available.
        def spEntityId = props.spEntityId
        //  this field is not empty, it overrides the default Entity ID for this Service Provider. Service Provider Entity IDs are usually a URL, like http://jenkins.example.org/.
        def maximumSessionLifetime = new Integer(props.maximumSessionLifetime)

        SamlAdvancedConfiguration advancedConfiguration = new SamlAdvancedConfiguration(forceAuthn, authnContextClassRef, spEntityId, maximumSessionLifetime)

        SamlEncryptionData encryptionData = null
        // todo: If we need ot encrypt SAML Signing Key
        // SamlEncryptionData encryptionData = new SamlEncryptionData(keystorePath, keystorePassword, privateKeyPassword, privateKeyAlias)

        def usernameCaseConversion = props.usernameCaseConversion


        String SAML2_REDIRECT_BINDING_URI = props.samlBindingMethod

        SamlSecurityRealm samlSecurity = new SamlSecurityRealm(idpMetadataConfiguration,
                displayNameAttributeName, groupsAttributeName, maximumAuthenticationLifetime,
                usernameAttributeName, emailAttributeName, logoutUrl, advancedConfiguration,
                encryptionData, usernameCaseConversion, SAML2_REDIRECT_BINDING_URI)

        Jenkins.get().setSecurityRealm(samlSecurity)
        Logger.global.info("[Config] Configuring Security Setting finished")
    }

    def configureRolesAccessManagement() {}

    def configureSalveAgent() {
        Jenkins.get().setSlaveAgentPort(50000)
    }

    def disableAuthentication() {
        Jenkins.get().disableSecurity() // No Authentication
    }

    def configureCloud() {
        try {
            Logger.global.info("Creating ECS Template")
            def ecsTemplates = templates = Arrays.asList(
                    //a t2.micro has 992 memory units & 1024 CPU units
                    // so you can run 1 java on t2.micro
                    createECSTaskTemplate('ecs-java', 'cloudbees/jnlp-slave-with-java-build-tools', 992, 1024),
                    // and 2 js on t2.micro
                    createECSTaskTemplate('ecs-javascript', 'cloudbees/jnlp-slave-with-java-build-tools', 496, 512)
            )
            String clusterArn = queryJenkinsClusterArn(region)

            Logger.global.info("Creating ECS Cloud for $clusterArn")
            def ecsCloud = new ECSCloud(
                    name = "jenkins_cluster",
                    templates = ecsTemplates,
                    credentialsId = '',
                    cluster = clusterArn,
                    regionName = region,
                    jenkinsUrl = instanceUrl,
                    slaveTimoutInSeconds = 60
            )

            Jenkins.get().clouds.clear()
            Jenkins.get().clouds.add(ecsCloud)
        } catch (com.amazonaws.SdkClientException e) {
            Logger.global.severe({ e.message })
            Logger.global.severe("ERROR: Could not create ECS config, are you running this container in AWS?")
        }
    }

    //cloudbees/jnlp-slave-with-java-build-tools
    ECSTaskTemplate createECSTaskTemplate(String label, String image, int softMemory, int cpu) {
        Logger.global.info("Creating ECS Template '$label' for image '$image' (memory: softMemory, cpu: $cpu)")
        new ECSTaskTemplate(
                templateName = label,
                label = label,
                image = image,
                remoteFSRoot = "/home/jenkins",
                //memory reserved
                memory = 0,
                //soft memory
                memoryReservation = softMemory,
                cpu = cpu,
                privileged = false,
                logDriverOptions = null,
                environments = null,
                extraHosts = null,
                mountPoints = null
        )
    }



    static void main(String[] args) {

        Logger.global.info("[Start] startup script")

        JenkinsConfigurator jc = new JenkinsConfigurator()

        jc.initJenkinsProperties()

        // Configuring Jenkins URL - cloud
        jc.configureJenkinsURL()

        // SAML2 Authentication
        jc.configureSecuritySettings()

        // Only Authenticated Users can Access Jenkins
        FullControlOnceLoggedInAuthorizationStrategy flas = new FullControlOnceLoggedInAuthorizationStrategy()
        flas.setAllowAnonymousRead(false)
        Jenkins.get().setAuthorizationStrategy(flas)

        // Configuring Roles and Access
        //jc.configureRolesAccessManagement()

        // Realm based Authentication
        //def hudsonRealm = new HudsonPrivateSecurityRealm(false)
        //hudsonRealm.createAccount("admin","admin")
        //Jenkins.get().setSecurityRealm(hudsonRealm)


        jc.configureCloud()
        jc.configureSalveAgent()


        Jenkins.get().save()

        // Creating Demo Job
        //jc.buildJob('seed', new ParametersAction(new StringParameterValue('NumberOfCopies', "5")))

        Logger.global.info("[Done] startup script")
    }
}
