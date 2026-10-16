{{/*
Names are derived from the Lembos component rather than the release, so two components deployed
into one namespace cannot collide and the object name is traceable back to the catalog entry.
*/}}
{{- define "webservice.name" -}}
{{- $c := .Values.lembos.component | default .Release.Name -}}
{{- $c | replace "/" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "webservice.fullname" -}}
{{- $n := include "webservice.name" . -}}
{{- if .Values.lembos.stamp -}}
{{- printf "%s-%s" $n .Values.lembos.stamp | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $n -}}
{{- end -}}
{{- end -}}

{{/* A pinned digest wins over a tag: a deployment pins what it resolved, and a tag can move. */}}
{{- define "webservice.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default "latest") -}}
{{- end -}}
{{- end -}}

{{- define "webservice.labels" -}}
app.kubernetes.io/name: {{ include "webservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: lembos
{{- /* A label value cannot hold "/": a qualified name is written with "." in its place. */}}
lembos.dev/component: {{ .Values.lembos.component | replace "/" "." | trunc 63 | trimSuffix "." | quote }}
lembos.dev/environment: {{ .Values.lembos.environment | replace "/" "." | trunc 63 | trimSuffix "." | quote }}
lembos.dev/stamp: {{ .Values.lembos.stamp | quote }}
lembos.dev/spec-version: {{ .Values.lembos.specVersion | quote }}
{{- end -}}

{{- define "webservice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "webservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "webservice.resources" -}}
{{- $size := .Values.sizeClass | default "small" -}}
{{- $spec := index .Values.sizes $size | default (index .Values.sizes "small") -}}
{{- toYaml $spec -}}
{{- end -}}

{{/* The first port marked public. Nil when the workload exposes nothing. */}}
{{- define "webservice.publicPort" -}}
{{- range .Values.ports -}}
{{- if .isPublic -}}{{ .port }}{{- break -}}{{- end -}}
{{- end -}}
{{- end -}}
