{{/*
Names are derived from the Lembos component rather than the release, so two components deployed
into one namespace cannot collide and the object name is traceable back to the catalog entry.
*/}}
{{- define "service.name" -}}
{{- $c := .Values.lembos.component | default .Release.Name -}}
{{- $c | replace "/" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service.fullname" -}}
{{- $n := include "service.name" . -}}
{{- if .Values.lembos.slot -}}
{{- printf "%s-%s" $n .Values.lembos.slot | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $n -}}
{{- end -}}
{{- end -}}

{{/* A pinned digest wins over a tag: a deployment pins what it resolved, and a tag can move. */}}
{{- define "service.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default "latest") -}}
{{- end -}}
{{- end -}}

{{- define "service.labels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: lembos
{{- /* A label value cannot hold "/": a qualified name is written with "." in its place. */}}
lembos.dev/component: {{ .Values.lembos.component | replace "/" "." | trunc 63 | trimSuffix "." | quote }}
lembos.dev/environment: {{ .Values.lembos.environment | replace "/" "." | trunc 63 | trimSuffix "." | quote }}
lembos.dev/slot: {{ .Values.lembos.slot | quote }}
{{- end -}}

{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "service.resources" -}}
{{- $size := .Values.sizeClass | default "small" -}}
{{- $spec := index .Values.sizes $size | default (index .Values.sizes "small") -}}
{{- toYaml $spec -}}
{{- end -}}

{{/* The first port marked public. Nil when the workload exposes nothing. */}}
{{- define "service.publicPort" -}}
{{- range .Values.ports -}}
{{- if .isPublic -}}{{ .port }}{{- break -}}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "service.publicPortName" -}}
{{- range .Values.ports -}}
{{- if .isPublic -}}{{ .name }}{{- break -}}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "service.listensOn80" -}}
{{- range .Values.ports -}}
{{- if eq (int .port) 80 -}}true{{- break -}}{{- end -}}
{{- end -}}
{{- end -}}

{{- /*
  What the workload depends on, as environment variables — where each thing is and where its credential lives,
  never the credential in a value. A resource binding names its endpoint (joined to its port where the module
  publishes the two apart), a URL where the resource publishes one that carries no secret, and its secret's path.
  The credential is read from that secret by key — the URL where a provisioner placed a whole one, else the username
  and password an operator writes (CloudNativePG's app secret) — each optional, so a pod still starts where a key is
  absent. An upstream is a component this one calls: a bare
  host is called over HTTP, on the port its Service answers every caller on.
*/}}
{{- define "service.dependencyEnv" -}}
{{- range $handle, $binding := .Values.resourceBindings }}
{{- $name := $handle | snakecase | upper }}
{{- with $binding.endpoint }}
- name: {{ $name }}_ENDPOINT
  {{- if and $binding.port (not (contains ":" .)) }}
  value: {{ printf "%s:%v" . $binding.port | quote }}
  {{- else }}
  value: {{ . | quote }}
  {{- end }}
{{- end }}
{{- with $binding.port }}
- name: {{ $name }}_PORT
  value: {{ . | quote }}
{{- end }}
{{- with $binding.url }}
- name: {{ $name }}_URL
  value: {{ . | quote }}
{{- end }}
{{- with $binding.secretRef }}
{{- $secret := . | replace "/" "-" | lower | trunc 253 }}
- name: {{ $name }}_SECRET_REF
  value: {{ . | quote }}
{{- if not $binding.url }}
- name: {{ $name }}_URL
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: url
      optional: true
{{- end }}
{{- range $key := list "username" "password" }}
- name: {{ $name }}_{{ upper $key }}
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: {{ $key }}
      optional: true
{{- end }}
{{- end }}
{{- end }}
{{- range $name, $address := .Values.upstreams }}
- name: UPSTREAM_{{ $name | snakecase | upper }}
  value: {{ ternary $address (printf "http://%s" $address) (contains "://" $address) | quote }}
{{- end }}
{{- end -}}

{{- /* Whether the slot's Key Vault holds any of this component's binding secrets, for the Key Vault provider. */}}
{{- define "service.keyVaultSecrets" -}}
{{- if and .Values.identity.azure.clientId .Values.identity.azure.keyVault -}}
{{- range $handle, $binding := .Values.resourceBindings -}}
{{- if $binding.secretRef -}}yes{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- /* The service account the pods run as: the slot's, where it gives one, else the chart's own, else none. */}}
{{- define "service.serviceAccountName" -}}
{{- if .Values.identity.serviceAccount -}}
{{ .Values.identity.serviceAccount }}
{{- else if .Values.serviceAccount.create -}}
{{ include "service.fullname" . }}
{{- end -}}
{{- end }}
