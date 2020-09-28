(import 'ksonnet-util/kausal.libsonnet') +
(import 'etcd-operator/etcd-cluster.libsonnet') + {
    _config:: {
        storage_account: error '_config.storage_account must be set',
        storage_account_key: error '_config.storage_account_key must be set',
        endpoint_protocol: 'https',
        api_domain: 'blob.core.windows.net',

        service_name: 'minio',

        users: {},
    },

    _images+:: {
        minio: 'minio/mino',
        mc: 'minio/mc'
    },

    gateway_etcd: $.etcd_cluster('minio-etcd'),

    local container = $.core.v1.container,
    local envFrom = container.envFromType,
    local statefulset = $.apps.v1.statefulSet,

    gateway_container:: container.new('minio', $._images.minio) +
        container.withArgs([
            "gateway", "azure", "%(endpoint_protocol)s://%(storage_account)s.%(api_domain)s" % $._config
        ]) +
        container.withEnvMap({
            "MINIO_ACCESS_KEY": $._config.storage_account,
            "MINIO_ETCD_ENDPOINTS": "http://%s-client:2379" % $.gateway_etcd.metadata.name
        }) +
        container.withEnvFromMixin([
            envFrom.mixin.secretRef.withName($.gateway_account_key.metadata.name)
        ]),

    gateway_statefulset: statefulset.new('minio-gateway', 3, [$.gateway_container], [], {}) +
        $.util.antiAffinityStatefulSet,

    local service = $.core.v1.service,
    gateway_service: service.new($._config.service_name),

    local secret = $.core.v1.secret,
    gateway_account_key: secret.new('minio-account-key') +
        secret.withData({
            "MINIO_SECRET_KEY": $._config.storage_account_key
        }),

    gateway_user_keys: secret.new('minio-user-keys') +
        secret.withData({
            [u]: if std.objectHas($._config.users[u], "secret_access_key") then std.base64($._config.users[u].secret_access_key) else error "no secret_access_key defined for user %s" % u
            for u in std.objectFields($._config.users)
        }),

    local configMap = $.core.v1.configMap,
    gateway_user_policies: configMap.new('minio-user-policies') +
        configMap.withData({
            [u]: if std.objectHas($._config.users[u], "policy") then std.manifestJson($._config.users[u].policy) else error "no policy defined for user %s" % u
            for u in std.objectFields($._config.users)
        }),
    
    gateway_user_job_container:: container.new('minio-user-setup', $._images.mc) +
        container.withCommand(["/bin/ash", "-c"]) +
        container.withArgs([(importstr 'user_setup.sh.tmpl') % $._config]) +
        container.withEnvFromMixin([
            envFrom.mixin.secretRef.withName($.gateway_account_key.metadata.name)
        ]) +
        container.withVolumeMounts([
            $.core.v1.volumeMount.new('policies', '/etc/minio/userSetup/policies', true),
            $.core.v1.volumeMount.new('keys', '/etc/minio/userSetup/keys', true),
        ]),

    local gateway_user_job_labels = {app: 'minio', job: 'user-setup'},
    local job = $.batch.v1.job,
    gateway_user_job: job.new() + job.mixin.metadata.withName("minio-user-setup") +
        job.mixin.metadata.withLabels(gateway_user_job_labels) +
        job.mixin.spec.selector.withMatchLabels(gateway_user_job_labels) +
        job.mixin.spec.template.metadata.withLabels(gateway_user_job_labels) +
        job.mixin.spec.template.spec.withContainers([$.gateway_user_job_container]) +
        job.mixin.spec.template.spec.withVolumes([
            $.core.v1.volume.fromConfigMap('policies', $.gateway_user_policies.metadata.name),
            $.core.v1.volume.fromSecret('keys', $.gateway_user_keys.metadata.name)
        ]),
}