import subprocess
import time
import signal
import atexit

# Global settings 🌍
server_ip, server_port, local_ip, auth = "x.x.x.x", "8000", "localhost", "akash:akash"
fixed_ports = [80, 443, 1317, 26656, 26657, 8443]
commands = []

# Terminate all subprocesses 🛑
def terminate_processes():
    print("🔌 Disconnecting all ports...")
    for cmd in commands:
        subprocess.run(["pkill", "-f", " ".join(cmd)])
    print("🎉 All ports disconnected! 🎉")

# Register termination function 📝
atexit.register(terminate_processes)

# Handle termination signals 🚨
def signal_handler(signum, frame):
    print(f"🚨 Received signal {signum}. Terminating...")
    terminate_processes()
    exit(1)

# Register signal handlers 🛡️
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

# Connect a range of ports 🌈
def connect_ports(port_list, protocol=""):
    base_command = ["chisel", "client", "--keepalive", "1m", "--auth", auth, f"{server_ip}:{server_port}"]
    port_commands = [f"R:{server_ip}:{port}:{local_ip}:{port}{protocol}" for port in port_list]
    command = base_command + port_commands
    commands.append(command)
    print(f"🔌 Connecting ports: {port_list} with protocol {protocol} 🚀")
    subprocess.Popen(command)
    time.sleep(10)

# Main function 🚀
def main():
    print("🌟 Starting the chisel client setup... 🌟")

    # Connect fixed ports first with TCP 🛠️
    connect_ports(fixed_ports, "/tcp")
    print(f"🎯 Fixed ports {fixed_ports} connected with TCP! 🎉")
    
    # Connect range of ports 🌈
    for i in range(30000, 32768, 500):
        connect_ports(range(i, min(i + 500, 32768)), "/tcp")
        time.sleep(5)
        connect_ports(range(i, min(i + 500, 32768)), "/udp")
        time.sleep(5)
    print("✨ All ports successfully connected! ✨")

    # Monitor and restart subprocesses 👀
    print("👀 Monitoring subprocesses... 👀")
    while True:
        for cmd in commands:
            if subprocess.run(["pgrep", "-f", " ".join(cmd)]).returncode != 0:
                print(f"🔄 Reconnecting chisel client: {' '.join(cmd)} 🚀")
                subprocess.Popen(cmd)
        time.sleep(60)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"😱 An exception occurred: {e} 😱")
        terminate_processes()
        exit(1)
