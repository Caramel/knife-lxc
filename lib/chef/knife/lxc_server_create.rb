require 'chef/knife'
require 'toft/node_controller'

module KnifeLxc

  class LxcServerCreate < Chef::Knife
    #include Toft
    
    deps do
      require 'chef/node'
      require 'chef/knife/bootstrap'
      Chef::Knife::Bootstrap.load_deps
    end
    
    banner "knife lxc server create -N NAME (options)"

    option :node_name,
      :short => "-N NAME",
      :long => "--node-name NAME",
      :description => "Container name and chef node name",
      :required => true

    option :node_ip,
      :long => "--ip IP",
      :description => "Ip for new container",
      :default => "192.168.20.#{(rand(222 - 100) +100)}"

    option :distro,
      :short => "-d DISTRO",
      :long => "--distro DISTRO",
      :description => "Bootstrap a lxc container using a template; default is 'lucid-chef'",
      :default => "lucid-chef"

    option :run_list,
      :short => "-r RUN_LIST",
      :long => "--run-list RUN_LIST",
      :description => "Comma separated list of roles/recipes to apply",
      :proc => lambda { |o| o.split(/[\s,]+/) },
      :default => []


    # This method will be executed when you run this knife command.
    def run
      puts "Creating lxc container '#{config[:node_name]}' with ip '#{config[:node_ip]}' from template '#{config[:distro]}'"
      node = Toft::NodeController.instance.create_node config[:node_name], {:ip => config[:node_ip], :type => config[:distro]}
      start_node node
      # HACK: is debian-specific
      run_ssh node, 'apt-get install -y wget ca-certificates'
      bootstrap_for_node(node).run
#      puts "Run chef client with run list: #{config[:run_list].join(' ')}"
#      run_chef node, config[:run_list], config[:environment]
      puts "Node created! Details: ip => #{node.ip}, name => #{node.hostname} "
    end

    private


    def start_node(node)
      # TODO: use node.start
      hostname = node.hostname
      puts "Starting host node..."
      system "lxc-start -n #{hostname} -d"
      system "lxc-wait -n #{hostname} -s RUNNING"
      puts "Waiting for sshd"
      print (".") until tcp_test_ssh(node.ip) { sleep 10 }
      puts " OK!"
    end

    # from knife-xenserver
    def bootstrap_for_node(node)
      bootstrap = Chef::Knife::Bootstrap.new
      bootstrap.name_args = [node.ip]
      bootstrap.config[:run_list] = config[:run_list]
      bootstrap.config[:first_boot_attributes] = config[:first_boot_attributes]
      bootstrap.config[:ssh_user] = 'root'
      bootstrap.config[:ssh_password] = 'root'
      bootstrap.config[:chef_node_name] = config[:chef_node_name] || node.hostname
      # bootstrap will run as root...sudo (by default) also messes up Ohai on CentOS boxes
      bootstrap.config[:use_sudo] = false
      bootstrap.config[:distro] = 'chef-full'
      bootstrap.config[:host_key_verify] = config[:host_key_verify]
      bootstrap
    end

    def run_chef(node, run_list, environment)
      set_run_list node.hostname, run_list
      env_string = environment.nil? ? "" : "-E #{environment}"
      run_ssh node, "chef-client -j /etc/chef/first-boot.json #{env_string}"
    end

    def run_ssh node, cmd
      # TODO: use node.run_ssh
      system "ssh #{node.ip} '#{cmd}'"
    end

    def set_run_list(hostname, entries)
      cnode = Chef::Node.load(hostname)
      cnode.run_list.run_list_ites.clear
      entries.each { |e| cnode.run_list << e }
      cnode.save
    end
    
    def tcp_test_ssh(hostname)
      tcp_socket = TCPSocket.new(hostname, 22)
      readable = IO.select([tcp_socket], nil, nil, 5)
      if readable
        yield
        true
      else
        false
      end
    rescue Errno::ETIMEDOUT
      false
    rescue Errno::EPERM
      false
    rescue Errno::ECONNREFUSED
      sleep 2
      false
    rescue Errno::EHOSTUNREACH
      sleep 2
      false
    ensure
      tcp_socket && tcp_socket.close
    end

  end
end
