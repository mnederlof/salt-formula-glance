{%- from "glance/map.jinja" import server with context %}
{%- if server.enabled %}

glance_packages:
  pkg.installed:
  - names: {{ server.pkgs }}

{%- if not salt['user.info']('glance') %}
glance_user:
  user.present:
    - name: glance
    - home: /var/lib/glance
    {# note: glance uid/gid values would not be evaluated after user is created. #}
    - uid: {{ server.get('glance_uid') }}
    - gid: {{ server.get('glance_gid') }}
    - shell: /bin/false
    - system: True
    - require_in:
      - pkg: glance_packages

glance_group:
  group.present:
    - name: glance
    {# note: glance uid/gid values would not be evaluated after user is created. #}
    - gid: {{ server.get('glance_gid') }}
    - system: True
    - require_in:
      - pkg: glance_packages
      - user: glance_user
{%- endif %}

/etc/glance/glance-cache.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-cache.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-registry.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-registry.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-scrubber.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-scrubber.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-api.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-api.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages

/etc/glance/glance-api-paste.ini:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-api-paste.ini
  - template: jinja
  - require:
    - pkg: glance_packages

{%- if server.version == 'newton' or server.version == 'ocata' %}

glance_glare_package:
  pkg.installed:
  - name: glance-glare

/etc/glance/glance-glare-paste.ini:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-glare-paste.ini
  - template: jinja
  - require:
    - pkg: glance_packages
    - pkg: glance_glare_package

/etc/glance/glance-glare.conf:
  file.managed:
  - source: salt://glance/files/{{ server.version }}/glance-glare.conf.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: glance_packages
    - pkg: glance_glare_package

{%- if not grains.get('noservices', False) %}

glance_glare_service:
  service.running:
  - enable: true
  - name: glance-glare
  - require_in:
    - cmd: glance_install_database
    - cmd: glance_load_metadatafs
  - watch:
    - file: /etc/glance/glance-glare.conf
    {%- if server.message_queue.get('ssl',{}).get('enabled',False) %}
    - file: rabbitmq_ca_glance_server
    {% endif %}
    {%- if server.database.get('ssl',{}).get('enabled',False)  %}
    - file: mysql_ca_glance_server
    {% endif %}

{%- endif %}
{%- endif %}

{%- set glance_glare_available = server.version in ['newton', 'ocata'] %}
{%- if glance_glare_available %}
  {%- set glance_services_list = server.services %}
{%- else %}
  {%- set glance_services_list = server.services + ['glance-glare'] %}
{%- endif %}

{%- if not grains.get('noservices', False) %}
{%- for service_name in glance_services_list %}
{{ service_name }}_default:
  file.managed:
    - name: /etc/default/{{ service_name }}
    - source: salt://glance/files/default
    - template: jinja
    - defaults:
        service_name: {{ service_name }}
        values: {{ server }}
    - require:
      - pkg: glance_packages
{%- if glance_glare_available %}
      - pkg: glance_glare_package
{%- endif %}
    - watch_in:
      - service: glance_services
{%- if glance_glare_available %}
      - service: glance_glare_service
{%- endif %}
{%- endfor %}
{%- endif %}

{%- if server.logging.log_appender %}

{%- if server.logging.log_handlers.get('fluentd', {}).get('enabled', False) %}
glance_fluentd_logger_package:
  pkg.installed:
    - name: python-fluent-logger
{%- endif %}

{% for service_name in glance_services_list %}
{{ service_name }}_logging_conf:
  file.managed:
    - name: /etc/glance/logging/logging-{{ service_name }}.conf
    - source: salt://glance/files/logging.conf
    - template: jinja
    - makedirs: True
    - user: glance
    - group: glance
    - defaults:
        service_name: {{ service_name }}
        values: {{ server }}
    - require:
      - pkg: glance_packages
{%- if glance_glare_available %}
      - pkg: glance_glare_package
{%- endif %}
{%- if server.logging.log_handlers.get('fluentd', {}).get('enabled', False) %}
      - pkg: glance_fluentd_logger_package
{%- endif %}
    - watch_in:
      - service: glance_services
{%- if glance_glare_available %}
      - service: glance_glare_service
{%- endif %}
{%- endfor %}

{%- endif %}

{% if server.storage.get('swift', {}).get('store', {}).get('references', {}) %}
/etc/glance/swift-stores.conf:
  file.managed:
  - source: salt://glance/files/_backends/_swift.conf
  - template: jinja
  - require:
    - pkg: glance_packages
  - watch_in:
    - service: glance_services
{% endif %}

{%- if not grains.get('noservices', False) %}

glance_services:
  service.running:
  - enable: true
  - names: {{ server.services }}
  - watch:
    - file: /etc/glance/glance-api.conf
    - file: /etc/glance/glance-registry.conf
    - file: /etc/glance/glance-api-paste.ini
    {%- if server.message_queue.get('ssl',{}).get('enabled',False) %}
    - file: rabbitmq_ca_glance_server
    {% endif %}
    {%- if server.database.get('ssl',{}).get('enabled',False)  %}
    - file: mysql_ca_glance_server
    {% endif %}

glance_install_database:
  cmd.run:
  - name: glance-manage db_sync
  - require:
    - service: glance_services

glance_load_metadatafs:
  cmd.run:
  - name: glance-manage db_load_metadefs
  - require:
    - cmd: glance_install_database

{%- if server.get('image_cache', {}).get('enabled', False) %}
glance_cron_glance-cache-pruner:
  cron.present:
  - name: glance-cache-pruner
  - user: glance
  - special: '@daily'
  - require:
    - service: glance_services

glance_cron_glance-cache-cleaner:
  cron.present:
  - name: glance-cache-cleaner
  - user: glance
  - minute: 30
  - hour: 5
  - daymonth: '*/2'
  - require:
    - service: glance_services

{%- endif %}

{%- endif %}

{%- if grains.get('virtual_subtype', None) == "Docker" %}

glance_entrypoint:
  file.managed:
  - name: /entrypoint.sh
  - template: jinja
  - source: salt://glance/files/entrypoint.sh
  - mode: 755

{%- endif %}

/srv/glance:
  file.directory:
  - mode: 755
  - user: glance
  - group: glance
  - require:
    - pkg: glance_packages

/var/lib/glance/images:
  file.directory:
  - mode: 755
  - user: glance
  - group: glance
  - require:
    - pkg: glance_packages

{%- for image in server.get('images', []) %}

glance_download_{{ image.name }}:
  cmd.run:
  - name: wget {{ image.source }}
  - unless: "test -e {{ image.file }}"
  - cwd: /srv/glance
  - require:
    - file: /srv/glance

glance_install_{{ image.name }}:
  cmd.wait:
  - name: source /root/keystonerc; glance image-create --name '{{ image.name }}' {% if image.visibility is defined %}--visibility {{ image.visibility }}{% else %}--is-public {{ image.public }}{% endif %} --container-format bare --disk-format {{ image.format }} < {{ image.file }}
  - cwd: /srv/glance
  - require:
    - service: glance_services
  - watch:
    - cmd: glance_download_{{ image.name }}

{%- endfor %}

{%- for image_name, image in server.get('image', {}).iteritems() %}

glance_download_{{ image_name }}:
  cmd.run:
  - name: wget {{ image.source }}
  - unless: "test -e {{ image.file }}"
  - cwd: /srv/glance
  - require:
    - file: /srv/glance

glance_install_image_{{ image_name }}:
  cmd.run:
  - name: source /root/keystonerc; glance image-create --name '{{ image_name }}' {% if image.visibility is defined %}--visibility {{ image.visibility }}{% else %}--is-public {{ image.public }}{% endif %} --container-format bare --disk-format {{ image.format }} < /srv/glance/{{ image.file }}
  - require:
    - service: glance_services
    - cmd: glance_download_{{ image_name }}
  - unless:
    - cmd: source /root/keystonerc && glance image-list | grep {{ image_name }}

{%- endfor %}

{%- if server.filesystem_store_metadata_file is defined %}
glance_filesystem_store_metadata_file:
  file.managed:
  - name: {{ server.get('filesystem_store_metadata_file', '/etc/glance/filesystem_store_metadata.json') }}
  - mode: 644
  - user: glance
  - group: glance
  - source: salt://glance/files/filesystem_store_metadata.json_template
  - template: jinja
  - require:
    - pkg: glance_packages
  - watch_in:
    - service: glance_services
{%- endif %}

{%- for name, rule in server.get('policy', {}).iteritems() %}

{%- if rule != None %}
rule_{{ name }}_present:
  keystone_policy.rule_present:
  - path: /etc/glance/policy.json
  - name: {{ name }}
  - rule: {{ rule }}
  - require:
    - pkg: glance_packages

{%- else %}

rule_{{ name }}_absent:
  keystone_policy.rule_absent:
  - path: /etc/glance/policy.json
  - name: {{ name }}
  - require:
    - pkg: glance_packages

{%- endif %}

{%- endfor %}

{%- if server.message_queue.get('ssl',{}).get('enabled', False) %}
rabbitmq_ca_glance_server:
{%- if server.message_queue.ssl.cacert is defined %}
  file.managed:
    - name: {{ server.message_queue.ssl.cacert_file }}
    - contents_pillar: glance:server:message_queue:ssl:cacert
    - mode: 0444
    - makedirs: true
{%- else %}
  file.exists:
   - name: {{ server.message_queue.ssl.get('cacert_file', server.cacert_file) }}
{% endif %}
{% endif %}

{%- if server.database.get('ssl',{}).get('enabled',False)  %}
mysql_ca_glance_server:
{%- if server.database.ssl.cacert is defined %}
  file.managed:
    - name: {{ server.database.ssl.cacert_file }}
    - contents_pillar: glance:server:database:ssl:cacert
    - mode: 0444
    - makedirs: true
{%- else %}
  file.exists:
   - name: {{ server.database.ssl.get('cacert_file', server.cacert_file) }}
{%- endif %}
{%- endif %}

{%- endif %}
