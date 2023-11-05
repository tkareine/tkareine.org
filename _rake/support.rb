# frozen_string_literal: true

module Support
  def self.command_exist?(cmd)
    pid = spawn("which #{cmd}", %i{out err} => '/dev/null')
    _, status = Process.waitpid2(pid)
    status.exitstatus == 0
  end
end
