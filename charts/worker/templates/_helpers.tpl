{{- define "worker.name" -}}
{{- $c := .Values.lembos.component | default .Release.Name -}}
{{- $c | replace "/" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "worker.fullname" -}}
{{- $n := include "worker.name" . -}}
{{- if .Values.lembos.slot -}}
{{- printf "%s-%s" $n .Values.lembos.slot | trunc 63 | trimSuffix "-" -}}
{{- else -}}{{- $n -}}{{- end -}}
{{- end -}}

{{- define "worker.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default "latest") -}}
{{- end -}}
{{- end -}}

{{- define "worker.labels" -}}
app.kubernetes.io/name: {{ include "worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: lembos
{{- /* A label value cannot hold "/": a qualified name is written with "." in its place. */}}
lembos.dev/component: {{ .Values.lembos.component | replace "/" "." | trunc 63 | trimSuffix "." | quote }}
lembos.dev/environment: {{ .Values.lembos.environment | replace "/" "." | trunc 63 | trimSuffix "." | quote }}
lembos.dev/slot: {{ .Values.lembos.slot | quote }}
{{- end -}}

{{- define "worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "worker.resources" -}}
{{- $size := .Values.sizeClass | default "small" -}}
{{- toYaml (index .Values.sizes $size | default (index .Values.sizes "small")) -}}
{{- end -}}

{{/* Shared by every chart: a binding names where the credential is, never what it is. */}}
{{- /*
  What the workload depends on, as environment variables — where each thing is and where its credential lives,
  never the credential. The same contract as service, so a component moving between the two keeps its wiring: a
  binding's endpoint, joined to its port, and secret path, its URL from a Kubernetes secret only where one was
  placed, and each upstream it calls.
*/}}
{{- define "worker.dependencyEnv" -}}
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
{{- with $binding.secretRef }}
- name: {{ $name }}_SECRET_REF
  value: {{ . | quote }}
- name: {{ $name }}_URL
  valueFrom:
    secretKeyRef:
      name: {{ . | replace "/" "-" | lower | trunc 253 }}
      key: url
      optional: true
{{- end }}
{{- end }}
{{- range $name, $address := .Values.upstreams }}
- name: UPSTREAM_{{ $name | snakecase | upper }}
  value: {{ ternary $address (printf "http://%s" $address) (contains "://" $address) | quote }}
{{- end }}
{{- end -}}

{{- /* Whether the slot's Key Vault holds any of this component's binding secrets, for the Key Vault provider. */}}
{{- define "worker.keyVaultSecrets" -}}
{{- if and .Values.identity.azure.clientId .Values.identity.azure.keyVault -}}
{{- range $handle, $binding := .Values.resourceBindings -}}
{{- if $binding.secretRef -}}yes{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- /* The service account the pods run as: the slot's, where it gives one, else the chart's own, else none. */}}
{{- define "worker.serviceAccountName" -}}
{{- if .Values.identity.serviceAccount -}}
{{ .Values.identity.serviceAccount }}
{{- else if .Values.serviceAccount.create -}}
{{ include "worker.fullname" . }}
{{- end -}}
{{- end }}
