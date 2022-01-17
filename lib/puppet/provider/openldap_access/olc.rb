require 'tempfile'

Puppet::Type.type(:openldap_access).provide(:olc) do

  # TODO: Use ruby bindings (can't find one that support IPC)

  defaultfor :osfamily => :debian, :osfamily => :redhat

  commands :slapcat => 'slapcat', :ldapmodify => 'ldapmodify'

  mk_resource_methods

  def self.instances
    # TODO: restict to bdb, hdb and globals

    i = []
    slapcat(
      '-b',
      'cn=config',
      '-H',
      'ldap:///???(olcAccess=*)'
    ).split("\n\n").collect do |paragraph|
      access = nil
      suffix = nil
      position = nil
      paragraph.gsub("\n ", '').split("\n").collect do |line|
        case line
        when /^olcDatabase: /
          suffix = "cn=#{line.split(' ')[1].gsub(/\{-?\d+\}/, '')}"
        when /^olcSuffix: /
          suffix = line.split(' ')[1] if not suffix
        when /^olcAccess: /
          position, what, bys = line.match(/^olcAccess:\s+\{(\d+)\}to\s+(\S+(?:\s+filter=\S+)?(?:\s+attrs=\S+)?)((\s+by\s+\S+\s+\S+)+)\s*$/).captures
          # p "suffix: #{suffix}"
          # p "position: #{position}"
          # p "what: #{what}"
          # p "bys: #{bys}"

          by_ = []
          access_ = []
          control_ = []
          bys.split(' by ')[1..-1].each { |b|
            by, access, control = b.strip.match(/^(\S+)\s+(\S+)(\s+\S+)?$/).captures
            by_.push(by)
            access_.push(access)
            control_.push(control)
	  }
          i << new(
              :name     => "to #{what} by #{bys} on #{suffix}",
              :ensure   => :present,
              :position => position,
              :what     => what,
              :by       => by_,
              :suffix   => suffix,
              :access   => access_,
              :control  => control_
          )
        end
      end
    end

    i
  end

  def self.prefetch(resources)
    # Get the accesses currently available in the database
    accesses = instances
    #p "accesses: #{accesses.map { |a| "(what: " + a.what + ', by: ' + a.by + ', suffix: ' + a.suffix + ")" }.join(" ")}"
    resources.keys.each do |name|
      #p "resource: #{name}"
      #p "  what: #{resources[name][:what]}"
      #p "  by: #{resources[name][:by]}"
      #p "  suffix: #{resources[name][:suffix]}"
      #p "  position: #{resources[name][:position]}"
      #p "  access: #{resources[name][:access]}"
      if provider = accesses.find{ |access|
          access.position == resources[name][:position] &&
          access.suffix == resources[name][:suffix]
      } 
        if provider.what == resources[name][:what] &&
              provider.by == resources[name][:by] &&
              provider.access == resources[name][:access]
          #p "No change"
          resources[name].provider = provider
        else
          #p "#{provider.by[0]}"
          #p "The provider #{provider} matches the position but the entries differ - create a new entry"
        end
      else 
        #p "No match"
      end
    end
    
    #accesses.each do |a|
    #  unless resources.values.find { |r| r.provider.equal? a }
    #      t = Tempfile.new('openldap_access')
    #      t << "dn: #{self.getDn(a.suffix)}\n"
    #      t << "changetype: modify\n"
    #      t << "delete: olcAccess\n"
    #      t << "olcAccess: {#{a.position}}\n"
    #      t.close
    #      Puppet.debug(IO.read t.path)
    #      ldapmodify('-Y', 'EXTERNAL', '-H', 'ldapi:///', '-f', t.path)
    #  end
    #end

  end

  def getDn(suffix)
    if suffix == 'cn=frontend'
      return 'olcDatabase={-1}frontend,cn=config'
    elsif suffix == 'cn=config'
      return 'olcDatabase={0}config,cn=config'
    elsif suffix == 'cn=monitor'
      slapcat(
        '-b',
        'cn=config',
        '-H',
        "ldap:///???(olcDatabase=monitor)"
      ).split("\n").collect do |line|
        if line =~ /^dn: /
          return line.split(' ')[1]
        end
      end
    elsif suffix == 'cn=bdb'
      slapcat(
        '-b',
        'cn=config',
        '-H',
        "ldap:///???(olcDatabase=bdb)"
      ).split("\n").collect do |line|
        if line =~ /^dn: /
          return line.split(' ')[1]
        end
      end
    else
      slapcat(
        '-b',
        'cn=config',
        '-H',
        "ldap:///???(olcSuffix=#{suffix})"
      ).split("\n").collect do |line|
        if line =~ /^dn: /
          return line.split(' ')[1]
        end
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    position = "{#{resource[:position]}}" if resource[:position]
    t = Tempfile.new('openldap_access')
    t << "dn: #{getDn(resource[:suffix])}\n"
    t << "add: olcAccess\n"
    t << "olcAccess: #{position}to #{resource[:what]}"
    resource[:by] = [resource[:by]] unless resource[:by].kind_of?(Array)
    access_ = resource[:access].split(" ")
    $i = 0
    until $i >= resource[:by].size do
      t << " by #{resource[:by][$i]} #{access_[$i]}"
      $i += 1;
    end
    t << "\n"
    t.close
    Puppet.debug(IO.read t.path)
    begin
      ldapmodify('-Y', 'EXTERNAL', '-H', 'ldapi:///', '-f', t.path)
    rescue Exception => e
      t = Tempfile.new('openldap_access')
      t << "dn: #{getDn(resource[:suffix])}\n"
      t << "replace: olcAccess\n"
      t << "olcAccess: #{position}to #{resource[:what]}"
      $i = 0
      until $i >= resource[:by].size do
        t << " by #{resource[:by][$i]} #{access_[$i]}"
        $i += 1;
      end    
      t << "\n"
      t.close
      ldapmodify('-Y', 'EXTERNAL', '-H', 'ldapi:///', '-f', t.path)
      #raise Puppet::Error, "LDIF content:\n#{IO.read t.path}\nError message: #{e.message}"
    end
  end

  def destroy
    t = Tempfile.new('openldap_access')
    t << "dn: #{getDn(@property_hash[:suffix])}\n"
    t << "changetype: modify\n"
    t << "delete: olcAccess\n"
    t << "olcAccess: {#{@property_hash[:position]}}\n"
    t.close
    Puppet.debug(IO.read t.path)
    slapdd('-b', 'cn=config', '-l', t.path)
  end

  def access=(value)
    t = Tempfile.new('openldap_access')
    t << "dn: #{getDn(@property_hash[:suffix])}\n"
    t << "changetype: modify\n"
    t << "delete: olcAccess\n"
    t << "olcAccess: {#{@property_hash[:position]}}\n"
    t << "-\n"
    t << "add: olcAccess\n"
    t << "olcAccess: {#{@property_hash[:position]}}to #{resource[:what]} by #{resource[:by]} #{resource[:access]}\n"
    t.close
    Puppet.debug(IO.read t.path)
    begin
      ldapmodify('-Y', 'EXTERNAL', '-H', 'ldapi:///', '-f', t.path)
    rescue Exception => e
      raise Puppet::Error, "LDIF content:\n#{IO.read t.path}\nError message: #{e.message}"
    end
  end

end
