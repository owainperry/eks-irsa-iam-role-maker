# eks-irsa-iam-role-maker

This component is used when using the cluster bootstrap controller to create IAM roles.

The problem that is being solved is that you might want to create iam roles for service accounts for components installed using CAPI and Flux  

there is a chicken egg where you need the trust policy of the cluster to add to the iam role for the service account you want to decorate with IAM permissions via IRSA  

all configuration is via envrionment variables at present.  

you will need to mount your iam permission json files to be added to the policy of the iam role in /var/policy/<here>.json  

Required:  

* NAME (name of the cluster)
* SA_NAMESPACE (service account namespace)
* SA_NAME (service account name)
* IAM_ROLE_NAME_PREFIX (the prefix for the iam role , which has '-$NAME' appended.)

Defaults:  

(you should not need to change these)

* API_SERVER default: https://kubernetes.default.svc
* SERVICE_ACCOUNT default: /var/run/secrets/kubernetes.io/serviceaccount")
* *POLICY_FOLDER default: /var/policy