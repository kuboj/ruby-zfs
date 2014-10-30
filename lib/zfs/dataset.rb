module ZFS
  class Dataset
    attr_reader :name
    attr_reader :pool
    attr_reader :path

    class NotFound < StandardError; end
    class AlreadyExists < StandardError; end
    class InvalidName < StandardError; end

    # Create a new ZFS object (_not_ filesystem).
    def initialize(name)
      @name, @pool, @path = name, *name.split('/', 2)
    end

    # Return the parent of the current filesystem, or nil if there is none.
    def parent
      p = Pathname(name).parent.to_s
      if p == '.'
        nil
      else
        ZFS(p)
      end
    end

    # Returns the children of this filesystem
    def children(opts = {})
      raise NotFound unless exist?

      cmd = [ZFS_PATH].flatten + %w(list -H -r -oname -tfilesystem)
      cmd << '-d1' unless opts[:recursive]
      cmd << name

      stdout, stderr, status = Open3.capture3(*cmd)
      if status.success? and stderr == ""
        stdout.lines.drop(1).collect do |filesystem|
          ZFS(filesystem.chomp)
        end
      else
        raise 'something went wrong'
      end
    end

    # Does the filesystem exist?
    def exist?
      cmd = [ZFS_PATH].flatten + %w(list -H -oname) + [name]

      out, status = Open3.capture2e(*cmd)
      if status.success? and out == "#{name}\n"
        true
      else
        false
      end
    end

    # Create filesystem
    def create(opts = {})
      return nil if exist?

      cmd = [ZFS_PATH].flatten + ['create']
      cmd << '-p' if opts[:parents]
      cmd += ['-V', opts[:volume]] if opts[:volume]
      cmd << name

      out, status = Open3.capture2e(*cmd)
      if status.success? and out.empty?
        self
      elsif out.match(/dataset already exists\n$/)
        nil
      else
        raise "something went wrong: #{out}, #{status}"
      end
    end

    # Destroy filesystem
    def destroy!(opts = {})
      raise NotFound if !exist?

      cmd = [ZFS_PATH].flatten + ['destroy']
      cmd << '-r' if opts[:children]
      cmd << name

      out, status = Open3.capture2e(*cmd)

      if status.success? and out.empty?
        true
      else
        raise "something went wrong: #{out}, #{status}"
      end
    end

    # Stringify
    def to_s
      "#<ZFS:#{name}>"
    end

    # ZFS's are considered equal if they are the same class and name
    def ==(other)
      other.class == self.class && other.name == self.name
    end

    def [](key)
      cmd = [ZFS_PATH].flatten + %w(get -ovalue -Hp) + [key.to_s, name]

      stdout, stderr, status = Open3.capture3(*cmd)

      if status.success? and stderr.empty? and stdout.lines.count == 1
        stdout.chomp
      else
        raise "something went wrong. #{stderr} #{stdout}"
      end
    end

    def []=(key, value)
      cmd = [ZFS_PATH].flatten + ['set', "#{key.to_s}=#{value}", name]

      out, status = Open3.capture2e(*cmd)

      if status.success? and out.empty?
        value
      else
        raise "something went wrong: #{out}, #{status}"
      end
    end

      # Define an attribute
    def self.property(name, opts = {})
      case opts[:type]
        when :size, :integer
          # FIXME: also takes :values. if :values is all-Integers, these are the only options. if there are non-ints, then :values is a supplement

          define_method name do
            Integer(self[name])
          end
          define_method "#{name}=" do |value|
            self[name] = value.to_s
          end if opts[:edit]

        when :boolean
          # FIXME: booleans can take extra values, so there are on/true, off/false, plus what amounts to an enum
          # FIXME: if options[:values] is defined, also create a 'name' method, since 'name?' might not ring true
          # FIXME: replace '_' by '-' in opts[:values]
          define_method "#{name}?" do
            self[name] == 'on'
          end
          define_method "#{name}=" do |value|
            self[name] = value ? 'on' : 'off'
          end if opts[:edit]

        when :enum
          define_method name do
            sym = (self[name] || "").gsub('-', '_').to_sym
            if opts[:values].grep(sym)
              return sym
            else
              raise "#{name} has value #{sym}, which is not in enum-list"
            end
          end
          define_method "#{name}=" do |value|
            self[name] = value.to_s.gsub('_', '-')
          end if opts[:edit]

        when :snapshot
          define_method name do
            val = self[name]
            if val.nil? or val == '-'
              nil
            else
              ZFS(val)
            end
          end

        when :float
          define_method name do
            Float(self[name])
          end
          define_method "#{name}=" do |value|
            self[name] = value
          end if opts[:edit]

        when :string
          define_method name do
            self[name]
          end
          define_method "#{name}=" do |value|
            self[name] = value
          end if opts[:edit]

        when :date
          define_method name do
            DateTime.strptime(self[name], '%s')
          end

        when :pathname
          define_method name do
            Pathname(self[name])
          end
          define_method "#{name}=" do |value|
            self[name] = value.to_s
          end if opts[:edit]

        else
          puts "Unknown type '#{opts[:type]}'"
      end
    end
    private_class_method :property

    property :available,            type: :size
    property :compressratio,        type: :float
    property :creation,             type: :date
    property :defer_destroy,        type: :boolean
    property :mounted,              type: :boolean
    property :origin,               type: :snapshot
    property :refcompressratio,     type: :float
    property :referenced,           type: :size
    property :type,                 type: :enum, values: [:filesystem, :snapshot, :volume]
    property :used,                 type: :size
    property :usedbychildren,       type: :size
    property :usedbydataset,        type: :size
    property :usedbyrefreservation, type: :size
    property :usedbysnapshots,      type: :size
    property :userrefs,             type: :integer

    property :aclinherit,           type: :enum,    edit: true, inherit: true, values: [:discard, :noallow, :restricted, :passthrough, :passthrough_x]
    property :atime,                type: :boolean, edit: true, inherit: true
    property :canmount,             type: :boolean, edit: true,                values: [:noauto]
    property :checksum,             type: :boolean, edit: true, inherit: true, values: [:fletcher2, :fletcher4, :sha256]
    property :compression,          type: :boolean, edit: true, inherit: true, values: [:lzjb, :gzip, :gzip_1, :gzip_2, :gzip_3, :gzip_4, :gzip_5, :gzip_6, :gzip_7, :gzip_8, :gzip_9, :zle]
    property :copies,               type: :integer, edit: true, inherit: true, values: [1, 2, 3]
    property :dedup,                type: :boolean, edit: true, inherit: true, values: [:verify, :sha256, 'sha256,verify']
    property :devices,              type: :boolean, edit: true, inherit: true
    property :exec,                 type: :boolean, edit: true, inherit: true
    property :logbias,              type: :enum,    edit: true, inherit: true, values: [:latency, :throughput]
    property :mlslabel,             type: :string,  edit: true, inherit: true
    property :mountpoint,           type: :pathname,edit: true, inherit: true
    property :nbmand,               type: :boolean, edit: true, inherit: true
    property :primarycache,         type: :enum,    edit: true, inherit: true, values: [:all, :none, :metadata]
    property :quota,                type: :size,    edit: true,                values: [:none]
    property :readonly,             type: :boolean, edit: true, inherit: true
    property :recordsize,           type: :integer, edit: true, inherit: true, values: [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
    property :refquota,             type: :size,    edit: true,                values: [:none]
    property :refreservation,       type: :size,    edit: true,                values: [:none]
    property :reservation,          type: :size,    edit: true,                values: [:none]
    property :secondarycache,       type: :enum,    edit: true, inherit: true, values: [:all, :none, :metadata]
    property :setuid,               type: :boolean, edit: true, inherit: true
    property :sharenfs,             type: :boolean, edit: true, inherit: true # FIXME: also takes 'share(1M) options'
    property :sharesmb,             type: :boolean, edit: true, inherit: true # FIXME: also takes 'sharemgr(1M) options'
    property :snapdir,              type: :enum,    edit: true, inherit: true, values: [:hidden, :visible]
    property :sync,                 type: :enum,    edit: true, inherit: true, values: [:standard, :always, :disabled]
    property :version,              type: :integer, edit: true,                values: [1, 2, 3, 4, :current]
    property :vscan,                type: :boolean, edit: true, inherit: true
    property :xattr,                type: :boolean, edit: true, inherit: true
    property :zoned,                type: :boolean, edit: true, inherit: true
    property :jailed,               type: :boolean, edit: true, inherit: true
    property :volsize,              type: :size,    edit: true

    property :casesensitivity,      type: :enum,    create_only: true, values: [:sensitive, :insensitive, :mixed]
    property :normalization,        type: :enum,    create_only: true, values: [:none, :formC, :formD, :formKC, :formKD]
    property :utf8only,             type: :boolean, create_only: true
    property :volblocksize,         type: :integer, create_only: true, values: [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
  end
end