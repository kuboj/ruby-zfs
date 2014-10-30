module ZFS
  class Filesystem < Dataset
    # Return sub-filesystem.
    def +(path)
      if path.match(/^@/)
        ZFS("#{name.to_s}#{path}")
      else
        path = Pathname(name) + path
        ZFS(path.cleanpath.to_s)
      end
    end

    # Rename filesystem.
    def rename!(newname, opts = {})
      raise AlreadyExists if ZFS(newname).exist?

      cmd = [ZFS_PATH].flatten + ['rename']
      cmd << '-p' if opts[:parents]
      cmd << name
      cmd << newname

      out, status = Open3.capture2e(*cmd)

      if status.success? and out.empty?
        initialize(newname)
        self
      else
        raise "something went wrong: #{out}, #{status}"
      end
    end

    # Create a snapshot.
    def snapshot(snapname, opts = {})
      raise NotFound, 'no such filesystem' unless exist?
      raise AlreadyExists, "#{snapname} exists" if ZFS("#{name}@#{snapname}").exist?

      cmd = [ZFS_PATH].flatten + ['snapshot']
      cmd << '-r' if opts[:children]
      cmd << "#{name}@#{snapname}"

      out, status = Open3.capture2e(*cmd)

      if status.success? and out.empty?
        ZFS("#{name}@#{snapname}")
      else
        raise "something went wrong: #{out}, #{status}"
      end
    end

    # Get an Array of all snapshots on this filesystem.
    def snapshots
      raise NotFound, 'no such filesystem' unless exist?

      stdout, stderr = [], []
      cmd = [ZFS_PATH].flatten + %w(list -H -d1 -r -oname -tsnapshot) + [name]

      stdout, stderr, status = Open3.capture3(*cmd)

      if status.success? and stderr.empty?
        stdout.lines.collect do |snap|
          ZFS(snap.chomp)
        end
      else
        raise "something went wrong: #{stderr}, #{stdout}"
      end
    end

    # Promote this filesystem.
    def promote!
      raise NotFound, 'filesystem is not a clone' if self.origin.nil?

      cmd = [ZFS_PATH].flatten + ['promote', name]

      out, status = Open3.capture2e(*cmd)

      if status.success? and out.empty?
        self
      else
        raise "something went wrong: #{out}, #{status}"
      end
    end
  end
end