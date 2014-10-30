module ZFS
  class Snapshot < Dataset
    # Return sub-filesystem
    def +(path)
      raise InvalidName if path.match(/@/)

      parent + path + name.sub(/^.+@/, '@')
    end

    # Just remove the snapshot-name
    def parent
      ZFS(name.sub(/@.+/, ''))
    end

    # Rename snapshot
    def rename!(newname, opts={})
      raise AlreadyExists if (parent + "@#{newname}").exist?

      newname = (parent + "@#{newname}").name

      cmd = [ZFS_PATH].flatten + ['rename']
      cmd << '-r' if opts[:children]
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

    # Clone snapshot
    def clone!(clone, opts={})
      clone = clone.name if clone.is_a? ZFS::Dataset

      raise AlreadyExists if ZFS::Dataset.new(clone).exist?

      cmd = [ZFS_PATH].flatten + ['clone']
      cmd << '-p' if opts[:parents]
      cmd << name
      cmd << clone

      out, status = Open3.capture2e(*cmd)

      if status.success? and out.empty?
        ZFS(clone)
      else
        raise "something went wrong: #{out}, #{status}"
      end
    end

    # Send snapshot to another filesystem
    def send_to(dest, opts={})
      incr_snap = nil
      dest = ZFS(dest)

      if opts[:incremental] and opts[:intermediary]
        raise ArgumentError, "can't specify both :incremental and :intermediary"
      end

      incr_snap = opts[:incremental] || opts[:intermediary]
      if incr_snap
        if incr_snap.is_a? String and incr_snap.match(/^@/)
          incr_snap = self.parent + incr_snap
        else
          incr_snap = ZFS(incr_snap)
          raise ArgumentError, "incremental snapshot must be in the same filesystem as #{self}" if incr_snap.parent != self.parent
        end

        snapname = incr_snap.name.sub(/^.+@/, '@')

        raise NotFound, "destination must already exist when receiving incremental stream" unless dest.exist?
        raise NotFound, "snapshot #{snapname} must exist at #{self.parent}" if self.parent.snapshots.grep(incr_snap).empty?
        raise NotFound, "snapshot #{snapname} must exist at #{dest}" if dest.snapshots.grep(dest + snapname).empty?
      elsif opts[:use_sent_name]
        raise NotFound, "destination must already exist when using sent name" unless dest.exist?
      elsif dest.exist?
        raise AlreadyExists, "destination must not exist when receiving full stream"
      end

      dest = dest.name if dest.is_a? ZFS
      incr_snap = incr_snap.name if incr_snap.is_a? ZFS

      send_opts = ZFS_PATH.flatten + ['send']
      send_opts.concat ['-i', incr_snap] if opts[:incremental]
      send_opts.concat ['-I', incr_snap] if opts[:intermediary]
      send_opts << '-R' if opts[:replication]
      send_opts << name

      receive_opts = ZFS_PATH.flatten + ['receive']
      receive_opts << '-d' if opts[:use_sent_name]
      receive_opts << dest

      Open3.popen3(*receive_opts) do |rstdin, rstdout, rstderr, rthr|
        Open3.popen3(*send_opts) do |sstdin, sstdout, sstderr, sthr|
          while !sstdout.eof?
            rstdin.write(sstdout.read(16384))
          end
          raise "stink" unless sstderr.read == ''
        end
      end
    end
  end
end