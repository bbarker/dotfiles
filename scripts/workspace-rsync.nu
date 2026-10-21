# XFS lists internal ACL storage under trusted.* for CAP_SYS_ADMIN callers.
# Rsync must not copy/delete those representations across filesystem types.
# -A and the independent getfacl comparison handle the effective POSIX ACLs.
# Adding an xattr filter overrides rsync's implicit namespace filtering, so
# preserve its normal root-side system.* exclusion explicitly as well.
# https://github.com/torvalds/linux/blob/master/fs/xfs/xfs_xattr.c
export const XATTR_FILTERS = [
    '--filter=-x system.*'
    '--filter=-x trusted.SGI_ACL_FILE'
    '--filter=-x trusted.SGI_ACL_DEFAULT'
]
