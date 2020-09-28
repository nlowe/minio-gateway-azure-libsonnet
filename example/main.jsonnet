local config = {
    _config+:: {
        namespace: 'minio',
        storage_account: 'foo',
        storage_account_key: 'supersecret',

        users: {
            'reader': {
                secret_access_key: 'readersecret',
                policy: {
                    Version: "2012-10-17",
                    Statement: [
                        {
                            Effect: "Allow",
                            Action: ["s3:ListAllMyBuckets", "s3:GetBucketLocation"],
                            Resource: ["*"],
                        },
                        {
                            Effect: "Allow",
                            Action: ["s3:ListBucket"],
                            Resource: ["arn:aws:s3:::my-prod-bucket"],
                        },
                        {
                            Action: ["s3:GetObject", "s3:ListObject"],
                            Effect: "Allow",
                            Resource: ["arn:aws:s3:::my-prod-bucket/*"],
                        },
                    ],
                },
            },
            'writer': {
                access_key: 'writer',
                secret_access_key: 'writersecret',
                policy: {
                    Version: "2012-10-17",
                    Statement: [
                        {
                            Effect: "Allow",
                            Action: ["s3:ListAllMyBuckets", "s3:GetBucketLocation"],
                            Resource: ["*"],
                        },
                        {
                            Effect: "Allow",
                            Action: ["*"],
                            Resource: ["arn:aws:s3:::my-prod-bucket"],
                        },
                    ],
                },
            },
        },
    }
};

// This is only required if you do not already have the operator deployed your cluster
local etcd_operator_objects = (import "etcd-operator/etcd-operator.libsonnet") + config;

(import "../minio-azure-gateway.libsonnet") +
{
    // Rename objects from the etcd operator so they're easy to identify
    ["etcd_operator_%s" % k]: etcd_operator_objects[k]
    for k in std.objectFields(etcd_operator_objects)
} + config
