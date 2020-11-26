FROM amazon/aws-cli:latest

RUN yum install -y zip jq
COPY entrypoint.sh /entrypoint.sh
COPY codeguru-reviewer-beta.json /codeguru-reviewer-beta.json
COPY codeguru-reviewer-beta.waiters-2.json /codeguru-reviewer-beta.waiters-2.json

ENTRYPOINT ["/entrypoint.sh"]
