{{/*
RuntimeAI Helm Chart — Template Helpers
*/}}

{{/* Chart name */}}
{{- define "runtimeai.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name */}}
{{- define "runtimeai.fullname" -}}
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

{{/* Common labels */}}
{{- define "runtimeai.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: runtimeai
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/* Selector labels for a specific service */}}
{{- define "runtimeai.selectorLabels" -}}
app: {{ .name }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .release }}
{{- end }}

{{/* Image reference: registry/name:tag */}}
{{- define "runtimeai.image" -}}
{{ .registry }}/{{ .name }}:{{ .tag }}
{{- end }}

{{/* Domain helpers */}}
{{- define "runtimeai.apiDomain" -}}
api.{{ .Values.global.subdomainPrefix }}.{{ .Values.global.domain }}
{{- end }}

{{- define "runtimeai.appDomain" -}}
app.{{ .Values.global.subdomainPrefix }}.{{ .Values.global.domain }}
{{- end }}

{{- define "runtimeai.esignDomain" -}}
esign.{{ .Values.global.subdomainPrefix }}.{{ .Values.global.domain }}
{{- end }}

{{- define "runtimeai.auditorDomain" -}}
auditor.{{ .Values.global.subdomainPrefix }}.{{ .Values.global.domain }}
{{- end }}

{{- define "runtimeai.saasDomain" -}}
saas.{{ .Values.global.subdomainPrefix }}.{{ .Values.global.domain }}
{{- end }}

{{- define "runtimeai.marketplaceDomain" -}}
marketplace.{{ .Values.global.subdomainPrefix }}.{{ .Values.global.domain }}
{{- end }}

{{- define "runtimeai.finopsDomain" -}}
finops.{{ .Values.global.subdomainPrefix }}.{{ .Values.global.domain }}
{{- end }}

{{/* CORS origins */}}
{{- define "runtimeai.corsOrigins" -}}
https://{{ include "runtimeai.appDomain" . }},https://{{ include "runtimeai.saasDomain" . }},https://{{ include "runtimeai.esignDomain" . }},https://{{ include "runtimeai.auditorDomain" . }},https://{{ include "runtimeai.marketplaceDomain" . }},https://{{ include "runtimeai.finopsDomain" . }}
{{- end }}
