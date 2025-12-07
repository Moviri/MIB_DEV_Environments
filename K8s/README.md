# Deployment Notes
In order to add the persistent volume, connect to the node via oc debug and connect to local FS to create two folders
```
oc debug node/<NODE_NAME>
# inside the debug shell:
chroot /host
mkdir -p /var/local/etl-pv/pv01
mkdir -p /var/local/etl-pv/pv02
exit
```
## Login to the Openshift
Follow [Confluence Notes](https://moviri-integrations.atlassian.net/wiki/x/AQArFw) to get connect to the Single Node Openshift (SNO) cluster on the Moviri Lab environment

After you log into the UI, click the kube-admin in the top right to get access to `Copy Login Command` and get the oc login token.
```
oc login --token=<TOKEN> --server=https://api.moviri-openshift.moviri-integrations.com:6443
```
### Apply deployment
```
oc apply -f test-deployment.yaml
```
### Clean up environment
```
oc delete -f test-deployment.yaml
```