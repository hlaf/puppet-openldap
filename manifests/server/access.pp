# See README.md for details.
define openldap::server::access (
  String[1]                            $what,
  Array[Openldap::Access_rule]         $access,
  Enum['present', 'absent']            $ensure   = 'present',
  Optional[Variant[Integer,String[1]]] $position = undef, # FIXME deprecated
  Optional[String[1]]                  $suffix   = undef, # FIXME deprecated
) {
  include openldap::server

  if $position or $suffix {
    warning('openldap::server::access position and suffix are deprecated')
  }

  Class['openldap::server::service']
  -> Openldap::Server::Access[$title]
  -> Class['openldap::server']

  openldap_access { $title:
    ensure   => $ensure,
    position => $position, # FIXME deprecated
    target   => $openldap::server::conffile,
    what     => $what,
    suffix   => $suffix, # FIXME deprecated
    access   => $access,
  }
}
