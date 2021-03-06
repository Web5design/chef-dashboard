# Unicorn-specific config
# Largely borrowed from the Github crew

app_dir = ::File.expand_path(::File.join(::File.dirname(__FILE__), ".."))
worker_processes 4

# Restart any workers that haven't responded in 30 seconds 
timeout 30

# Load the Rack app into the master before forking workers
# for super-fast worker spawn times
preload_app true

socket_file = app_dir + '/unicorn.sock'

unless File.directory?(File.dirname(socket_file))
  require 'fileutils'
  FileUtils::Verbose.mkdir_p File.dirname(socket_file)
end

# Listen on a Unix data socket
listen 'unix:' + socket_file, :backlog => 2048

##
# REE
# http://www.rubyenterpriseedition.com/faq.html#adapt_apps_for_cow
if GC.respond_to?(:copy_on_write_friendly=)
  GC.copy_on_write_friendly = true
end

before_fork do |server, worker|
  ##
  # When sent a USR2, Unicorn will suffix its pidfile with .oldbin and
  # immediately start loading up a new version of itself (loaded with a new
  # version of our app). When this new Unicorn is completely loaded
  # it will begin spawning workers. The first worker spawned will check to
  # see if an .oldbin pidfile exists. If so, this means we've just booted up
  # a new Unicorn and need to tell the old one that it can now die. To do so
  # we send it a QUIT.
  #
  # Using this method we get 0 downtime deploys.
 
  old_pid = app_dir + '/unicorn.pid.oldbin'
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  ##
  # Unicorn master is started as root, which is fine, but let's
  # drop the workers to mongrel:mongrel (or whatever you like...)
  begin
    uid, gid = Process.euid, Process.egid
    user, group = 'rails', 'rails'
    target_uid = Etc.getpwnam(user).uid
    target_gid = Etc.getgrnam(group).gid
    worker.tmp.chown(target_uid, target_gid)
    if uid != target_uid || gid != target_gid
      Process.initgroups(user, target_gid)
      Process::GID.change_privilege(target_gid)
      Process::UID.change_privilege(target_uid)
    end

    log_dir = File.join(app_dir, 'log')

    File.mkdir(log_dir, 0700) rescue nil

    $stdout.reopen(File.join(log_dir, 'stdout.log'), 'a')
    $stderr.reopen(File.join(log_dir, 'stderr.log'), 'a')
  rescue => e
    if ENV['RACK_ENV'] == 'development'
      STDERR.puts "couldn't change user, oh well"
    else
      raise e
    end
  end
end
