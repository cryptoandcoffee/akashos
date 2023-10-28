from kubernetes import client, config
import requests
import subprocess
from concurrent.futures import ThreadPoolExecutor
from tqdm import tqdm
import threading
import argparse
import time

# Initialize a lock for thread-safe tqdm updates
lock = threading.Lock()
WELCOME_MESSAGE_SENT = False

def should_skip_namespace(namespace, exclude_namespaces):
    return namespace in exclude_namespaces

def send_discord_message(message, context=None):
    DISCORD_WEBHOOK_URL = ""
    if context is not None:
        message = f"Namespace {context} was deleted due to the following reason: {message}"

    data = {"content": message}
    response = requests.post(DISCORD_WEBHOOK_URL, data=data)

    if response.status_code == 204:
        print("Message sent successfully to Discord!")
    else:
        print(f"Failed to send message to Discord. Status code: {response.status_code}, Response: {response.text}")

def send_pushover_notification(message, context=None):
    PUSHOVER_API_URL = "https://api.pushover.net/1/messages.json"
    API_TOKEN = ""
    USER_KEY = ""
    title = "Cluster Protection Alert" if context else "Cluster Protection Startup"

    data = {
        "token": API_TOKEN,
        "user": USER_KEY,
        "title": title,
        "message": message
    }
    response = requests.post(PUSHOVER_API_URL, data=data)
    if response.status_code == 200:
        print("Message sent successfully to Pushover!")
    else:
        print(f"Failed to send message to Pushover. Status code: {response.status_code}, Response: {response.text}")

def send_startup_message(discord_flag, pushover_flag):
    global WELCOME_MESSAGE_SENT

    if WELCOME_MESSAGE_SENT:
        return

    message = "Starting to protect cluster with Provider Chaperone by Crypto and Coffee."

    if discord_flag:
        send_discord_message(message)

    if pushover_flag:
        send_pushover_notification(message)

    WELCOME_MESSAGE_SENT = True

def check_keyword_files(namespace, pod_name, keywords, issues):
    command = ["kubectl", "exec", "-n", namespace, pod_name, "--", "find", "/", "-type", "f", "-size", "+1c"]
    for keyword in keywords:
        modified_command = command + ["-iname", f"*{keyword}*"]
        output = subprocess.run(modified_command, capture_output=True, text=True)
        if keyword in output.stdout:
            # Split the output by newline to get a list of file paths
            file_paths = output.stdout.strip().split('\n')
            # Append the issues with filename and location
            for file_path in file_paths:
                issues.append(f"Keyword '{keyword}' found in file: {file_path} in pod {pod_name}")

def check_image_name(image_name, common_torrent_clients, common_vpn_socks_clients, issues):
    for client in common_torrent_clients + common_vpn_socks_clients:
        if client in image_name:
            issues.append(f"Pod uses a common client image: {client}")

def check_files(namespace, pod_name, file_types, issues):
    command = ["kubectl", "exec", "-n", namespace, pod_name, "--", "find", "/", "-type", "f", "-size", "+1c"]
    for file_type in file_types:
        modified_command = command + ["-iname", f"*.{file_type}"]
        output = subprocess.run(modified_command, capture_output=True, text=True)
        if file_type in output.stdout:
            issues.append(f"We found a file with {file_type} extension in pod {pod_name}")

def check_processes(namespace, pod_name, file_types, issues):
    command = ["kubectl", "exec", "-n", namespace, pod_name, "--", "ps", "aux"]
    output = subprocess.run(command, capture_output=True, text=True)
    for file_type in file_types:
        if file_type in output.stdout:
            issues.append(f"We found a process running with {file_type} match in pod {pod_name}")

def check_pod(pod, exclude_namespaces, common_torrent_clients, common_vpn_socks_clients, file_types, keywords, issues, namespaces_to_delete, pbar):
    pod_name = pod.metadata.name
    namespace = pod.metadata.namespace
    image_name = pod.spec.containers[0].image

    if should_skip_namespace(namespace, exclude_namespaces):
        with lock:
            pbar.update(1)
        return

    local_issues = []  # Use a local list to store issues for this specific pod

    check_keyword_files(namespace, pod_name, keywords, local_issues)
    check_image_name(image_name, common_torrent_clients, common_vpn_socks_clients, local_issues)
    check_files(namespace, pod_name, file_types, local_issues)
    check_processes(namespace, pod_name, file_types, local_issues)

    with lock:
        issues.extend(local_issues)  # Extend the global issues list with local issues
        if local_issues:  # Only add the namespace to the delete set if issues were found
            namespaces_to_delete.add(namespace)
        pbar.update(1)

    if local_issues:
        return (namespace, local_issues)  # Return a tuple containing the namespace and the list of reasons

def delete_namespace(namespace, reasons, discord_flag, pushover_flag):
    try:
        v1.delete_namespace(name=namespace)
        print(f"Deleted namespace: {namespace}")
        if discord_flag:
            reason_str = "\n".join(reasons)
            send_discord_message(reason_str, namespace)
        if pushover_flag:
            reason_str = "\n".join(reasons)
            send_pushover_notification(reason_str, namespace)
    except Exception as e:
        print(f"Failed to delete namespace {namespace}: {e}")

def main(args):
    # Send startup message if Discord or Pushover are enabled
    send_startup_message(args.discord, args.pushover)

    config.load_kube_config()
    global v1
    v1 = client.CoreV1Api()

    exclude_namespaces = ["akash-services", "kube-system", "ingress-nginx", "lens-metrics", "rook-ceph", "nvidia-device-plugin"]
    common_torrent_clients = ["honeygain", "qbittorrent", "utorrent", "bittorrent", "deluge", "transmission", "vuze", "frostwire", "tixati", "bitcomet", "bitlord", "ekho", "dperson", "emule", "popcorntime", "headphones", "jackett", "lidarr", "mylar3", "prowlarr", "sickrage"]
    common_vpn_socks_clients = ["webtop", "dvpn", "mullvad", "softether", "openvpn", "wireguard", "nordvpn", "expressvpn", "ipvanish", "cyberghost", "tunnelbear", "vyprvpn", "hotspotshield", "surfshark", "dante", "3proxy", "ss5", "sunssh", "wingate", "ccproxy", "antinat", "srelay", "delegate", "shadowsocks"]
    file_types = ["torrent", "magnet", "xxx", "par2", "par", "epub", "mobi", "azw", "azw3", "fb2", "pdb", "cbz", "cbr", "djvu", "ibooks", "oxps", "xps", "cbr", "cbz"]
    keywords = ["porn,erotic,xxx"] #like sex, drugs, gore etc, is very sensitive to test first without --delete-namespaces


    all_pods = v1.list_pod_for_all_namespaces(watch=False).items
    filtered_pods = [pod for pod in all_pods if not should_skip_namespace(pod.metadata.namespace, exclude_namespaces)]

    issues = []
    namespaces_to_delete = set()

    with tqdm(total=len(filtered_pods), desc="Processing Pods") as pbar:
        with ThreadPoolExecutor() as executor:
            results = list(executor.map(lambda pod: check_pod(pod, exclude_namespaces, common_torrent_clients, common_vpn_socks_clients, file_types, keywords, issues, namespaces_to_delete, pbar), filtered_pods))

    print("\nIssues found:")
    for issue in issues:
        print(issue)

    if args.delete_namespaces:
        for result in results:
            if result:  # Check if there's a valid result (not None)
                namespace, reasons = result
                delete_namespace(namespace, reasons, args.discord, args.pushover)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Check for issues in Kubernetes pods.')
    parser.add_argument('--delete-namespaces', action='store_true', help='Delete namespaces that have issues.')
    parser.add_argument('--discord', action='store_true', help='Send notifications to Discord when deleting namespaces.')
    parser.add_argument('--pushover', action='store_true', help='Send notifications to Pushover when deleting namespaces.')
    parser.add_argument('--time', type=str, default="", help='Run the application for a given time duration. Examples: --1h, --10m, --forever.')

    args = parser.parse_args()

    time_mapping = {
        'forever': None,
        '1h': 3600,
        '10m': 600,
        '1m': 60,
        '30s': 30,
        # Add more mappings here
    }

    run_time = time_mapping.get(args.time, 0)

    while True:
        main(args)
        if run_time is None:
            print("Sleeping before next iteration...")
            time.sleep(5)
        elif run_time == 0:
            break
        else:
            print(f"Sleeping for {run_time} seconds before next iteration...")
            time.sleep(run_time)
