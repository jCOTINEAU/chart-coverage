{{- /*
TEST HELPERS - Various patterns for coverage testing
These helpers receive root context (.) to allow coverage tracking
*/ -}}

{{- /* Helper with simple if/else - uses root context */ -}}
{{- define "helper.ifElse" -}}
{{- if .Values.helperTest.enabled }}
enabled: true
{{- else }}
enabled: false
{{- end }}
{{- end -}}

{{- /* Helper with inline if/else - uses root context */ -}}
{{- define "helper.inline" -}}
value: {{ if .Values.helperTest.custom }}{{ .Values.helperTest.custom | quote }}{{ else }}"default"{{ end }}
{{- end -}}

{{- /* Helper without conditions */ -}}
{{- define "helper.static" -}}
static: "value"
{{- end -}}

{{- /* Helper using tpl with embedded template syntax - tests quote detection */ -}}
{{- define "helper.tplRender" -}}
{{- $value := .Values.tplTest.template | default "default-value" }}
{{- if contains "{{" $value }}
{{- tpl (cat "{{- with .scope -}}" $value "{{- end }}") (dict "scope" .Values.tplTest.scope "Values" .Values) }}
{{- else }}
{{- $value }}
{{- end }}
{{- end -}}

{{- /* Helper that receives a simple value (not root context) - tests graceful handling */ -}}
{{- define "helper.formatValue" -}}
{{- if gt (int .) 100 -}}
large
{{- else -}}
small
{{- end -}}
{{- end -}}

{{- /* Helper that receives dict with "context" key - common pattern */ -}}
{{- define "helper.withContext" -}}
{{- $component := .component -}}
{{- $ctx := .context -}}
{{- if eq $component "primary" -}}
priority: high
{{- else -}}
priority: normal
{{- end -}}
{{- end -}}
