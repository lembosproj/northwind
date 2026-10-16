{{- define "worker.name" -}}
{{- $c := .Values.lembos.component | default .Release.Name -}}
{{- $c | replace "/" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "worker.fullname" -}}
{{- $n := include "worker.name" . -}}
{{- if .Values.lembos.stamp -}}
{{- printf "%s-%s" $n .Values.lembos.stamp | trunc 63 | trimSuffix "-" -}}
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
lembos.dev/stamp: {{ .Values.lembos.stamp | quote }}
lembos.dev/spec-version: {{ .Values.lembos.specVersion | quote }}
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
{{- define "worker.bindingEnv" -}}
{{- range $handle, $binding := .Values.resourceBindings }}
- name: {{ $handle | upper | replace "-" "_" }}_URL
  valueFrom:
    secretKeyRef:
      name: {{ $binding.secretRef | replace "/" "-" }}
      key: url
{{- end }}
{{- end -}}
