# git-config-server — a tiny smart-HTTP git server for the GitOps config delivery.
#
# WHY IT EXISTS. The unified-ingress spokes un-bake their file-provider dynamic config: instead
# of baking dynamic.yaml into user_data (which makes any config change a VM RECREATION), each
# gateway git-pulls it from a repo hosted in the hub cluster and hot-reloads via
# --providers.file.watch. terraform pushes changes to that repo. Both the push (operator) and
# the pull (every spoke, on-prem AND cloud) have to reach the server the SAME way, and the only
# path that already works uniformly everywhere is the hub's :443 ingress (the route the spokes
# already use for collector.<domain>). So this serves git over SMART HTTP, exposed at
# git.<domain> through Traefik — not git:// or a NodePort, which would each need per-platform
# networking.
#
# Apache + git-http-backend (git's own canonical ScriptAlias config — lighttpd's mod_cgi
# mangles PATH_INFO for git-http-backend). Anonymous read AND write: a short-lived demo on a
# private lab net with no token (deliberate — see terraform/config-server/git);
# http.receivepack=true (set per-repo in entrypoint.sh) is what opens anonymous PUSH.
FROM alpine:3.20

# git-daemon owns /usr/libexec/git-core/git-http-backend (NOT the base `git` package).
RUN apk add --no-cache git git-daemon apache2 \
  && rm -f /etc/apache2/conf.d/*.conf

COPY httpd-git.conf /etc/apache2/conf.d/git.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV GIT_ROOT=/srv/git
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
