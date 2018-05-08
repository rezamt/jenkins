### Jenkins Automation using Terraform and ECS




### Getting Jenkins Installed Plugins

```bash

curl -s -k "http://admin:admin@localhost:8080/pluginManager/api/json?depth=1" | jq -r '.plugins[] | {plugin: .shortName,  version: .version} | tee plugins.txt'

```


All Jenkins Plugins are available under:

https://github.com/jenkinsci

Example: 

- Role Strategy Plugin https://github.com/jenkinsci/role-strategy-plugin
- Metrics Plugin https://github.com/jenkinsci/metrics-plugin
- Notification Plugin https://github.com/jenkinsci/notification-plugin


### Configuring HealthCheck
```bash
http://localhost:8080/metrics/YOUR-METRICS-KEY/


http://localhost:8080/metrics/cCCi7O8MOmuAqonqBtsc_R-xPeG2E5Jl0qr2NYXtHUNBNej7vZ2H_DrCupJ5RbyG/healthcheck?pretty=true


Create $JENKINS_HOME/jenkins.metrics.api.MetricsAccessKey.xml


<?xml version='1.1' encoding='UTF-8'?>
<jenkins.metrics.api.MetricsAccessKey_-DescriptorImpl plugin="metrics@3.1.2.11">
  <accessKeys>
    <jenkins.metrics.api.MetricsAccessKey>
      <key>cCCi7O8MOmuAqonqBtsc_R-xPeG2E5Jl0qr2NYXtHUNBNej7vZ2H_DrCupJ5RbyG</key>
      <description>Health check configuration</description>
      <canPing>true</canPing>
      <canThreadDump>false</canThreadDump>
      <canHealthCheck>true</canHealthCheck>
      <canMetrics>true</canMetrics>
    </jenkins.metrics.api.MetricsAccessKey>
  </accessKeys>
</jenkins.metrics.api.MetricsAccessKey_-DescriptorImpl>


```
