FROM alpine:3.18.3 as kubectl
RUN apk --update --no-cache add curl && \
    curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && \
	mv kubectl /usr/bin/ && chmod +x /usr/bin/kubectl

FROM atlassian/pipelines-awscli:1.25.19
COPY --from=kubectl /usr/bin/kubectl /usr/bin/kubectl