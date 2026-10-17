{{- define "slot.labels" -}}
app.kubernetes.io/managed-by: lembos
app.kubernetes.io/part-of: {{ .Release.Name }}
lembos.dev/stamp: {{ .Release.Namespace }}
lembos.dev/stage: {{ .Values.stage }}
{{- range $key, $value := .Values.dimensions }}
lembos.dev/{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Staging and prod name their callers; below them a namespace talks to anything, as on the AWS landing zone. */}}
{{- define "slot.restricted" -}}
{{- if has .Values.stage (list "staging" "prod") }}true{{ end -}}
{{- end -}}
