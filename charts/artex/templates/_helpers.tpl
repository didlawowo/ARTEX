{{/* Chart name, overridable. */}}
{{- define "artex.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified name: release name unless it already contains the chart name. */}}
{{- define "artex.fullname" -}}
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

{{- define "artex.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels. */}}
{{- define "artex.labels" -}}
helm.sh/chart: {{ include "artex.chart" . }}
{{ include "artex.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Selector labels: immutable, so they must not carry the chart version. */}}
{{- define "artex.selectorLabels" -}}
app.kubernetes.io/name: {{ include "artex.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "artex.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "artex.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Secret the pod reads: the release one, or an operator-provided one. */}}
{{- define "artex.secretName" -}}
{{- default (include "artex.fullname" .) .Values.secrets.existingSecret }}
{{- end }}

{{- define "artex.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
