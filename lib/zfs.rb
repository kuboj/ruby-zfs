require 'pathname'
require 'date'
require 'open3'

require_relative 'zfs/dataset'
require_relative 'zfs/filesystem'
require_relative 'zfs/snapshot'
require_relative 'zfs/version'

module ZFS
  ZFS_PATH   = 'zfs'
  ZPOOL_PATH = 'zpool'

  def self.pools
    cmd = [ZPOOL_PATH].flatten + %w(list -Honame)

    stdout, stderr, status = Open3.capture3(*cmd)

    if status.success? and stderr.empty?
      stdout.lines.map { |pool| ZFS(pool.chomp) }
    else
      raise 'something went wrong'
    end
  end

  def self.mounts
    cmd = [ZFS_PATH].flatten + %w(get -rHp -oname,value mountpoint)

    stdout, stderr, status = Open3.capture3(*cmd)

    if status.success? and stderr.empty?
      mounts = stdout.lines.map do |line|
        fs, path = line.chomp.split(/\t/, 2)
        [path, ZFS(fs)]
      end
      Hash[mounts]
    else
      raise 'something went wrong'
    end
  end
end

# Get ZFS object.
def ZFS(path)
  return path if path.is_a? ZFS::Dataset

  path = Pathname(path).cleanpath.to_s

  if path.match(/^\//)
    ZFS.mounts[path]
  elsif path.match('@')
    ZFS::Snapshot.new(path)
  else
    ZFS::Filesystem.new(path)
  end
end
