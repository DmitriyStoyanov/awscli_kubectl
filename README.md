[![Docker Pulls](https://img.shields.io/docker/pulls/scorpio2002/awscli_kubectl)](https://hub.docker.com/r/scorpio2002/awscli_kubectl/tags?page=1&ordering=last_updated)

# awscli_kubectl

Repo for creation of image with aws cli and kubectl

## CD

Dockerhub integrated with this repo and triggers automatically from master branch with creating image `scorpio2002/awscli_kubectl:latest`

## example of usage with jenkins pipeline

As example we can use it to create secrets for aws ecr access from kubernetes cluster to build and push docker images in jenkins

`aws-registry.yml`
```yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: aws-registry
spec:
  schedule: "* */8 * * *"
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 2
  jobTemplate:
    spec:
      backoffLimit: 4
      template:
        spec:
          serviceAccountName: ecr-account
          automountServiceAccountToken: true
          terminationGracePeriodSeconds: 0
          restartPolicy: Never
          containers:
          - name: kubectl
            imagePullPolicy: IfNotPresent
            image: scorpio2002/awscli_kubectl:latest
            command:
            - "/bin/sh"
            - "-c"
            - |
              AWS_ACCOUNT=123456789012 # your AWS account ID
              AWS_REGION=us-east-1 # your AWS ECR region
              DOCKER_REGISTRY_SERVER=https://${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com
              DOCKER_USER=AWS
              DOCKER_PASSWORD=`aws ecr get-login --region ${AWS_REGION} --registry-ids ${AWS_ACCOUNT} | cut -d' ' -f6`

              kubectl delete secret aws-registry || true
              kubectl create secret docker-registry aws-registry \
              --docker-server=$DOCKER_REGISTRY_SERVER \
              --docker-username=$DOCKER_USER \
              --docker-password=$DOCKER_PASSWORD \
              --docker-email=no@email.local
```

`ecr-account.yml`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ecr-account
  namespace: kubernetes-plugin
automountServiceAccountToken: false
imagePullSecrets:
- name: aws-registry
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 namespace: kubernetes-plugin
 name: ecr-role
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 name: ecr-role-binding
 namespace: kubernetes-plugin
subjects:
- kind: ServiceAccount
  name: ecr-account
  namespace: kubernetes-plugin
roleRef:
 kind: Role
 name: ecr-role
 apiGroup: rbac.authorization.k8s.io
```

and then example of job pipeline to use it in jenkins with connected kubernetes plugin
```groovy
def buildAndPushImage(String dockerFile, String imageName) {
  def image = docker.build(imageName,'-f ' + dockerFile + ' .')
  image.inside() {
    sh 'env' // here you can place test for your image
  }
  image.push()
}

pipeline {
  agent {
    kubernetes {
      //cloud 'kubernetes'
      label 'build-pod'
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins/kube-default: true
    app: jenkins
    component: agent
spec:
  containers:
    - name: docker
      image: docker:18-dind
      securityContext:
        privileged: true
      volumeMounts:
        - name: dind-storage
          mountPath: /var/lib/docker
        - name: aws-registry
          mountPath: /root/.docker/secret
  volumes:
    - name: dind-storage
      hostPath:
        path: /tmp/dind-storage
    - name: aws-registry
      secret:
        secretName: aws-registry
"""
    }
  }
  stages {
    stage('Build Docker image') {
      steps {
        git 'https://github.com/DmitriyStoyanov/docker-shellcheck' // git repo where needed Dockerfile for image placed
        container('docker') {
          script {
            sh 'cp /root/.docker/secret/.dockerconfigjson ~/.docker/config.json'
            buildAndPushImage('Dockerfile', '123456789012.dkr.ecr.us-east-1.amazonaws.com/shellcheck:latest')
            sh 'docker images'
          }
        }
      }
    }
  }
}
```
