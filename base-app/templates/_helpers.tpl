{{/*
Expand the name of the chart.
*/}}
{{- define "base-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "base-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "base-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "base-app.labels" -}}
helm.sh/chart: {{ include "base-app.chart" . }}
{{ include "base-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "base-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "base-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "base-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "base-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
parentRefs for the HTTPRoute. The Gateway itself is not managed by this chart.
Explicit httpRoute.parentRefs win. Otherwise one ref per hostname is generated,
pointing at the listener https-<hostname> of this release's ListenerSet, or of
httpRoute.gateway directly when httpRoute.listenerSet is disabled.
*/}}
{{- define "base-app.httpRoute.parentRefs" -}}
{{- if .Values.httpRoute.parentRefs -}}
{{- toYaml .Values.httpRoute.parentRefs -}}
{{- else -}}
{{- if not .Values.httpRoute.hostnames -}}
{{- fail "httpRoute needs either parentRefs or hostnames, default parentRefs are derived from the hostnames (sectionName https-<hostname>)" -}}
{{- end -}}
{{- $gw := .Values.httpRoute.gateway -}}
{{- $refs := list -}}
{{- range $host := .Values.httpRoute.hostnames -}}
{{- $section := include "base-app.listenerName" $host -}}
{{- if and $.Values.httpRoute.enabled $.Values.httpRoute.listenerSet.enabled -}}
{{- $refs = append $refs (dict "group" "gateway.networking.k8s.io" "kind" "ListenerSet" "name" (include "base-app.fullname" $) "sectionName" $section) -}}
{{- else -}}
{{- $refs = append $refs (dict "name" $gw.name "namespace" $gw.namespace "sectionName" $section) -}}
{{- end -}}
{{- end -}}
{{- toYaml $refs -}}
{{- end -}}
{{- end }}

{{/*
Listener name for a hostname, https-<hostname>. Takes the hostname as context.
*/}}
{{- define "base-app.listenerName" -}}
{{- if contains "*" . -}}
{{- fail (printf "httpRoute.hostnames entry %q is a wildcard, no listener name can be derived from it. Set httpRoute.parentRefs explicitly and disable httpRoute.listenerSet" .) -}}
{{- end -}}
https-{{ . }}
{{- end }}

{{/*
Name of the TLS secret holding the certificate for the hostnames.
*/}}
{{- define "base-app.tls.secretName" -}}
{{- .Values.tls.certificate.secretName | default (printf "%s-tls" (include "base-app.fullname" .)) -}}
{{- end }}

{{/*
Gateway namespaces the effective parentRefs point to, excluding the release
namespace. Rendered as a YAML list, used for the TLS secret ReferenceGrant.
*/}}
{{- define "base-app.gatewayNamespaces" -}}
{{- $namespaces := list -}}
{{- range $ref := include "base-app.httpRoute.parentRefs" . | fromYamlArray -}}
{{- $ns := default $.Release.Namespace $ref.namespace -}}
{{- if and (eq (default "Gateway" $ref.kind) "Gateway") (ne $ns $.Release.Namespace) -}}
{{- $namespaces = append $namespaces $ns -}}
{{- end -}}
{{- end -}}
{{- $namespaces | uniq | toYaml -}}
{{- end }}

{{/*
Gateway implementation the routePolicies are rendered for.
*/}}
{{- define "base-app.routePolicies.provider" -}}
{{- $p := .Values.routePolicies.provider | default "envoy" -}}
{{- if not (has $p (list "envoy" "nginx")) -}}
{{- fail (printf "routePolicies.provider must be envoy or nginx, got %q" $p) -}}
{{- end -}}
{{- $p -}}
{{- end }}

{{/*
Envoy Gateway local rate limit rules. ClientIP and Header use Distinct
selectors, so every client IP / header value gets its own bucket.
*/}}
{{- define "base-app.rateLimit.envoyRules" -}}
{{- $rl := .Values.routePolicies.rateLimit -}}
{{- if not (has $rl.unit (list "Second" "Minute" "Hour" "Day" "Month" "Year")) -}}
{{- fail (printf "routePolicies.rateLimit.unit must be one of Second, Minute, Hour, Day, Month, Year for Envoy, got %q" $rl.unit) -}}
{{- end -}}
{{- $limit := dict "requests" (int $rl.requests) "unit" $rl.unit -}}
{{- $rules := list -}}
{{- if eq $rl.key "ClientIP" -}}
{{- range $cidr := list "0.0.0.0/0" "::/0" -}}
{{- $rules = append $rules (dict "clientSelectors" (list (dict "sourceCIDR" (dict "type" "Distinct" "value" $cidr))) "limit" $limit) -}}
{{- end -}}
{{- else if eq $rl.key "Header" -}}
{{- if not $rl.headerName -}}
{{- fail "routePolicies.rateLimit.headerName is required when key is Header" -}}
{{- end -}}
{{- $rules = append $rules (dict "clientSelectors" (list (dict "headers" (list (dict "name" $rl.headerName "type" "Distinct")))) "limit" $limit) -}}
{{- else -}}
{{- fail (printf "routePolicies.rateLimit.key must be ClientIP or Header, got %q" $rl.key) -}}
{{- end -}}
{{- toYaml $rules -}}
{{- end }}

{{/*
Service port the HTTPRoute sends traffic to. Defaults to the first service port.
*/}}
{{- define "base-app.httpRoute.backendPort" -}}
{{- if .Values.httpRoute.backendPort -}}
{{- .Values.httpRoute.backendPort -}}
{{- else -}}
{{- (index .Values.service.ports 0).servicePort -}}
{{- end -}}
{{- end }}

{{/*
HTTPRoute the policies attach to. Policies are scoped to this application, so
they always target the route owned by this release.
*/}}
{{- define "base-app.policyTargetRoute" -}}
{{- if not .Values.httpRoute.enabled -}}
{{- fail "routePolicies require httpRoute.enabled=true, they attach to the HTTPRoute owned by this release" -}}
{{- end -}}
{{- include "base-app.fullname" . -}}
{{- end }}

{{/*
Rate in the r/s or r/m form expected by the NGINX limit_req directive.
*/}}
{{- define "base-app.rateLimit.rate" -}}
{{- $rl := .Values.routePolicies.rateLimit -}}
{{- if eq $rl.unit "Second" -}}
{{ $rl.requests }}r/s
{{- else if eq $rl.unit "Minute" -}}
{{ $rl.requests }}r/m
{{- else -}}
{{- fail (printf "routePolicies.rateLimit.unit must be Second or Minute, NGINX limit_req supports no other rates, got %q" $rl.unit) -}}
{{- end -}}
{{- end }}

{{/*
NGINX variable the rate limit buckets on.
*/}}
{{- define "base-app.rateLimit.key" -}}
{{- $rl := .Values.routePolicies.rateLimit -}}
{{- if eq $rl.key "ClientIP" -}}
$binary_remote_addr
{{- else if eq $rl.key "Header" -}}
{{- if not $rl.headerName -}}
{{- fail "routePolicies.rateLimit.headerName is required when key is Header" -}}
{{- end -}}
$http_{{ $rl.headerName | lower | replace "-" "_" }}
{{- else -}}
{{- fail (printf "routePolicies.rateLimit.key must be ClientIP or Header, got %q" $rl.key) -}}
{{- end -}}
{{- end }}

{{/*
CORS filter for the HTTPRoute. CORS is part of the core Gateway API rather than
an NGINX Gateway Fabric CRD, so it rides on the route instead of a policy.
Empty fields are dropped so the rendered filter only carries what was asked for.
*/}}
{{- define "base-app.httpRoute.corsFilter" -}}
{{- $cors := .Values.routePolicies.cors -}}
{{- if not $cors.allowOrigins -}}
{{- fail "routePolicies.cors.enabled=true requires allowOrigins, a CORS filter without an origin rejects every cross-origin request" -}}
{{- end -}}
{{- range $origin := $cors.allowOrigins -}}
{{- if hasSuffix "/" $origin -}}
{{- fail (printf "routePolicies.cors.allowOrigins entry %q must not end in a slash, an origin is scheme://host[:port]" $origin) -}}
{{- end -}}
{{- end -}}
{{- if and $cors.allowCredentials (has "*" $cors.allowOrigins) -}}
{{- fail "routePolicies.cors.allowCredentials cannot be combined with the * origin, browsers reject credentialed requests against a wildcard. List the origins explicitly" -}}
{{- end -}}
{{- if lt (int $cors.maxAge) 0 -}}
{{- fail (printf "routePolicies.cors.maxAge must not be negative, got %d" (int $cors.maxAge)) -}}
{{- end -}}
{{- $spec := dict -}}
{{- range $field := list "allowOrigins" "allowMethods" "allowHeaders" "exposeHeaders" -}}
{{- with index $cors $field -}}
{{- $_ := set $spec $field . -}}
{{- end -}}
{{- end -}}
{{- if $cors.allowCredentials -}}
{{- $_ := set $spec "allowCredentials" true -}}
{{- end -}}
{{- if gt (int $cors.maxAge) 0 -}}
{{- $_ := set $spec "maxAge" (int $cors.maxAge) -}}
{{- end -}}
{{- dict "type" "CORS" "cors" $spec | toYaml -}}
{{- end }}
