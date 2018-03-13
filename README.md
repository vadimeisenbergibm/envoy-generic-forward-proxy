# Envoy as a generic forward proxy
This sample shows how [Envoy](https://www.envoyproxy.io) can be used as a generic forward proxy on Kubernetes. "Generic" means that it will allow proxying any host, not a predefined set of hosts.

## Introduction
Suppose we need a Kubernetes service named `forward-proxy`. The service will be used as a forward proxy to *an arbitrary host*. The service must satisfy the following requirements:

1. The following request should be proxied to httbin.org/headers:
  `curl forward-proxy/headers -H "host: httpbin.org" -H "foo: bar"`

2. The following request should be proxied to https://edition.cnn.com, with TLS origination performed by the forward proxy:
  `curl -v forward-proxy:443 -H "host: edition.cnn.com"`

   Note that the request to the forward proxy is sent over HTTP. The forward proxy opens a TLS connection to
  https://edition.cnn.com .

3. A nice-to-have feature: use the `forward_proxy` as HTTP proxy.
  `http_proxy=forward-proxy:80 curl httpbin.org/headers -H "foo: bar"`

4. Another nice-to-have feature, to show Envoy's capabilities as a sidecar proxy. Transparently catch all the traffic inside the pod with the `forward-proxy` container and direct the traffic through the proxy. Use `iptables` for directing the traffic.

5. Use Envoy's filters for monitoring, transforming, policing the traffic that goes through the forward proxy.

6. Add SNI while performing TLS origination.

This sample shows how Envoy together with [nginx](https://www.nginx.com) can satisfy the requirements above. The requirement 5 is satisfied trivially, by using Envoy. Nginx is used for the _generic_ forward proxy functionality. While Envoy can function perfectly as a forward proxy for predefined hosts, it cannot satisfy the requirement 1. Envoy can satisfy the requirement 4, using [orignal destination](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/service_discovery.html#arch-overview-service-discovery-types-original-destination) clusters. However, even for this requirement there are issues. First, Envoy forwards the request by the destination IP, not by the host header. This way, policing the requests cannot be performed based on the destination host, since Envoy will send the request by the IP anyway. A malicious application can issue a request to a malicious IP with a valid host name. Envoy will check the host name, but will not be able to verify that the host name matches the IP. Nginx can forward the request by the host header, disregarding the original destination IP.
Second, Envoy will not be able to set SNI correctly for an arbitrary site, based on the Host header, see [this comment] (https://github.com/envoyproxy/envoy/issues/2670#issuecomment-369347351). Nginx can set [SNI](https://en.wikipedia.org/wiki/Server_Name_Indication) based on the Host header, using [proxy_ssl_server_name directive](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_server_name). Let's add the additional requirements:

7. When being used as a sidecar proxy, the `forward-proxy` must direct the traffic by the Host header, not by the original IP.

8. When performing TLS origination, the `forward-proxy` must set SNI according to the Host header.

Using Envoy in tandem with Nginx seems to satisfy the requirements cleanly. Envoy will direct all the traffic to Nginx instances running as forward proxies. Most of the features of Envoy, in particular its [HTTP Filters](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http_filters) will be available, while Nginx will complement Envoy, providing missing features for proxying to arbitrary sites.

In this sample, I demonstrate two cases:
1. Using Envoy with nginx as a generic forward proxy for other pods (other pods can access arbitrary hosts via the forward proxy)
2. Using Envoy with nginx as a sidecar generic forward proxy (the application in the pod can access arbitrary hosts via the forward proxy)

## Building and Pushing to the docker hub
Perform this step if you want to run your own version of the forward proxy. Alternatively, skip this step and use the version in https://hub.docker.com/u/vadimeisenbergibm .

`./build_and_push_docker.sh <your docker hub user name>`.

## Envoy as a generic forward proxy to other pods

### Deployment to Kubernetes
1. Edit `forward_proxy.yaml`: replace `vadimeisenbergibm` with your docker hub username. Alternatively, just use the images from https://hub.docker.com/u/vadimeisenbergibm .

2. Deploy the forward proxy:
`kubectl apply -f forward_proxy.yaml`

3. Deploy a pod to issue `curl` commands. I use the `sleep` pod from the [Istio samples](https://github.com/istio/istio/tree/master/samples), however any other pod with `curl` installed is good enough.
`kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/sleep/sleep.yaml`

### Test HTTP
* From any container with curl perform:

  `curl forward-proxy/headers -H "host: httpbin.org" -H "foo: bar"`

  or, alternatively:

  `http_proxy=forward-proxy:80 curl httpbin.org/headers -H "foo: bar"`

* After each call, check the logs to verify that the traffic indeed went through both Envoy and nginx:

  * Nginx logs

    `kubectl logs forward-proxy nginx`

     you should see log lines similar to:

     `127.0.0.1 - - [02/Mar/2018:06:32:39 +0000] "GET http://httpbin.org/headers HTTP/1.1" 200 191 "-" "curl/7.47.0"`

  * Envoy stats

    `kubectl exec -it forward-proxy -c envoy -- curl localhost:8001/stats | grep http.forward_http.downstream_rq`

    Check the number of `http.forward_http.downstream_rq_2xx` - the number of times 2xx code was returned.

### Test HTTPS (TLS origination)
  `curl -v forward-proxy:80 -H "host: edition.cnn.com"`

  will return _301 Moved Permanently_, _location:_ https://edition.cnn.com/ .

  The same result for:

  `http_proxy=forward-proxy:80 curl -v edition.cnn.com`

  We need to perform TLS origination for cnn.com:

  `curl -v forward-proxy:443 -H "host: edition.cnn.com"`

  or

  `http_proxy=forward-proxy:443 curl -v edition.cnn.com`

  Note that we performed HTTP call and used an HTTP proxy (`http_proxy`) to connect to edition.cnn.com via HTTPS. We send requests by HTTP, and the `forward-proxy` performs TLS origination for us.

## Envoy as a sidecar generic forward proxy
### Deployment to Kubernetes
1. Edit `sidecar_forward_proxy.yaml`: replace `vadimeisenbergibm` with your docker hub username. Alternatively, just use the images from https://hub.docker.com/u/vadimeisenbergibm .

2. Deploy the forward proxy:
`kubectl apply -f sidecar_forward_proxy.yaml`

### Testing
Get a shell into the `sleep` container of the `sidecar-forward-proxy` pod:

`kubectl exec -it sidecar-forward-proxy -c sleep bash`

* Test the nginx proxy

  `http_proxy=localhost:8080 curl http://httpbin.org/headers -H "foo: bar"`

* Test the envoy proxy with nginx proxy. Note that here the traffic is catched by iptables and forwarded to the Envoy proxy.

  `curl httpbin.org/headers -H "foo:bar"`

  `curl edition.cnn.com:443`

  Note the HTTP call to the port 443. Nginx will perform TLS origination.

*  Verify in nginx logs and Envoy stats that the traffic indeed passed thru Envoy and nginx.
   * Nginx logs

     `kubectl logs sidecar-forward-proxy nginx`

      you should see log lines similar to:

      `127.0.0.1 - - [02/Mar/2018:06:32:39 +0000] "GET http://httpbin.org/headers HTTP/1.1" 200 191 "-" "curl/7.47.0"`

    * Envoy stats

      `kubectl exec -it sidecar-forward-proxy -c envoy -- curl localhost:8001/stats | grep http.forward_http.downstream_rq`

       Check the number of `http.forward_http.downstream_rq_2xx` - the number of times 2xx code was returned.

## Technical details
* allow_absolute_urls directive
* proxy_ssl_server_name directive
* nginx listens on the localhost, to reduce attack vectors.
* iptables catch all the traffic, except for the users _root_ and _www-data_. Excluding _www-data_ from envoy's traffic control is required since nginx workers run as _www-data_.
