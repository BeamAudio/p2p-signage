import re
import json
from datetime import datetime

def parse_log_file(log_file_path):
    with open(log_file_path, 'r', encoding='utf-8') as f:
        logs = f.read().splitlines()

    parsed_logs = []
    for log in logs:
        log = log.strip()
        # Pattern for node sending a message to another node
        match = re.search(r'^(node\d+): Sending message to (node\d+): (.*)$', log)
        if match:
            source = match.group(1)
            destination = match.group(2)
            message_str = match.group(3)
            try:
                message_json = json.loads(message_str)
                msg_type = message_json.get('type', 'json')
            except json.JSONDecodeError:
                msg_type = 'text'

            parsed_logs.append({
                'source': source,
                'destination': destination,
                'protocol': 'P2P',
                'type': msg_type,
                'info': message_str
            })
            continue

        # Pattern for a node receiving a message
        match = re.search(r'^(node\d+): Received message from ([\d\.]+):\d+: (.*)$', log)
        if match:
            destination = match.group(1)
            source_ip = match.group(2)
            message_str = match.group(3)
            try:
                message_json = json.loads(message_str)
                sender = message_json.get('sender', 'unknown')
                message_content = json.loads(message_json.get('message', '{}'))
                msg_type = message_content.get('type', 'json')
                source = sender # The real source is in the message payload
            except (json.JSONDecodeError, TypeError):
                msg_type = 'text'
                source = source_ip

            parsed_logs.append({
                'source': source,
                'destination': destination,
                'protocol': 'P2P',
                'type': msg_type,
                'info': message_str
            })
            continue

        # Pattern for UDP Transport sending a message
        match = re.search(r'^UDPTransport: Sending message to ([\d\.]+):(\d+): (.*)$', log)
        if match:
            destination = f'{match.group(1)}:{match.group(2)}'
            message_str = match.group(3)
            try:
                message_json = json.loads(message_str)
                source = message_json.get('sender', 'unknown')
                message_content = json.loads(message_json.get('message', '{}'))
                msg_type = message_content.get('type', 'json')
            except (json.JSONDecodeError, TypeError):
                msg_type = 'text'
                source = 'unknown'

            parsed_logs.append({
                'source': source,
                'destination': destination,
                'protocol': 'UDP',
                'type': msg_type,
                'info': message_str
            })
            continue

        # New pattern for UDP_LOG from Dart
        match = re.search(r'^\[UDP_LOG\] \[(IN|OUT)\] \[([\d\.:]+)\] \[([\d]+)\] \[([\d\.]+):([\d]+)\] \[(.*)\]$', log)
        if match:
            direction = match.group(1)
            timestamp_str = match.group(2)
            local_port = match.group(3)
            remote_address = match.group(4)
            remote_port = match.group(5)
            message_preview = match.group(6)

            # Parse timestamp (assuming a dummy date for comparison)
            today = datetime.now().date()
            timestamp = datetime.strptime(f'{today} {timestamp_str}', '%Y-%m-%d %H:%M:%S.%f')

            source = ''
            destination = ''

            if direction == 'IN':
                source = f'{remote_address}:{remote_port}'
                destination = f'localhost:{local_port}'
            else:
                source = f'localhost:{local_port}'
                destination = f'{remote_address}:{remote_port}'

            msg_type = 'UDP_DATA' # Default type, can be refined later if message content is parsed
            try:
                message_json = json.loads(message_preview)
                if 'type' in message_json:
                    msg_type = message_json['type']
            except json.JSONDecodeError:
                pass # Not a JSON message, keep default type

            parsed_logs.append({
                'timestamp': timestamp,
                'source': source,
                'destination': destination,
                'protocol': 'UDP',
                'type': msg_type,
                'info': message_preview
            })
            continue

    return parsed_logs
def print_wireshark_style(parsed_logs):
    if not parsed_logs:
        print("No logs to display.")
        return

    print(f"{'Time':<15} {'Source':<25} {'Destination':<25} {'Protocol':<10} {'Type':<15} {'Info'}")
    print("-" * 140)

    in_count = 0
    out_count = 0

    start_time = parsed_logs[0]['timestamp']

    for log in parsed_logs:
        relative_time = (log['timestamp'] - start_time).total_seconds()
        source = log['source']
        destination = log['destination']
        protocol = log['protocol']
        msg_type = log['type']
        info = log['info']
        
        if 'localhost' in destination:
            in_count += 1
        else:
            out_count += 1

        # Color coding
        color_code = '\033[0m' # Reset
        if msg_type == 'ack':
            color_code = '\033[92m' # Green
        elif msg_type == 'gossip':
            color_code = '\033[94m' # Blue
        elif msg_type == 'auth':
            color_code = '\033[93m' # Yellow
        elif protocol == 'UDP':
            color_code = '\033[90m' # Dark Gray for generic UDP

        print(f"{color_code}{relative_time:<15.6f} {source:<25} {destination:<25} {protocol:<10} {msg_type:<15} {info[:50]}...\033[0m")

    print("\n" + "=" * 140)
    print(f"Total Packets: {len(parsed_logs)}")
    print(f"Incoming Packets: {in_count}")
    print(f"Outgoing Packets: {out_count}")
    print("=" * 140)

    # Simple Timeline Visualization
    print("\n" + "Time Plot (Relative Seconds):")
    print("-" * 140)

    # Group packets into 1-second intervals for the timeline
    timeline_intervals = {}
    for log in parsed_logs:
        relative_time = (log['timestamp'] - start_time).total_seconds()
        interval = int(relative_time) # Group by second
        if interval not in timeline_intervals:
            timeline_intervals[interval] = []
        timeline_intervals[interval].append(log['type'])

    max_interval = max(timeline_intervals.keys()) if timeline_intervals else 0

    for i in range(max_interval + 1):
        events = timeline_intervals.get(i, [])
        timeline_str = f'{i:<5}s | '
        for event_type in events:
            if event_type == 'ack':
                timeline_str += 'A' # Acknowledge
            elif event_type == 'gossip':
                timeline_str += 'G' # Gossip
            elif event_type == 'auth':
                timeline_str += 'H' # Auth
            else:
                timeline_str += '.' # Other UDP data
        print(timeline_str)
    print("-" * 140)

def generate_sequence_diagram_plantuml(parsed_logs):
    plantuml_output = []
    plantuml_output.append("@startuml")
    plantuml_output.append("skinparam monochrome true")

    participants = set()
    for log in parsed_logs:
        participants.add(log['source'])
        participants.add(log['destination'])

    # Declare participants, sorting for consistent order
    for p in sorted(list(participants)):
        # Replace special characters for PlantUML participant names
        participant_name = p.replace(':', '_').replace('.', '_')
        plantuml_output.append(f"participant {participant_name}")

    plantuml_output.append("") # Add a newline for readability

    for log in parsed_logs:
        sender = log['source'].replace(':', '_').replace('.', '_')
        receiver = log['destination'].replace(':', '_').replace('.', '_')
        message_type = log['type']
        message_info = log['info'][:30] + '...' if len(log['info']) > 30 else log['info']

        # Determine message arrow based on direction (inferred from source/destination)
        # For simplicity, assuming 'localhost' is always the local machine
        if 'localhost' in log['source']:
            # Outgoing message from local machine
            arrow = "->"
        else:
            # Incoming message to local machine
            arrow = "<-"

        plantuml_output.append(f"{sender} {arrow} {receiver}: [{message_type}] {message_info}")

    plantuml_output.append("@enduml")
    return "\n".join(plantuml_output)

def generate_activity_diagram_plantuml(parsed_logs):
    plantuml_output = []
    plantuml_output.append("@startuml")
    plantuml_output.append("skinparam monochrome true")

    plantuml_output.append("start")

    for i, log in enumerate(parsed_logs):
        message_type = log['type']
        activity_description = f"{message_type} ({i})"

        if 'localhost' in log['source']:
            # Outgoing message from local host
            plantuml_output.append(f"#green:Local Host sends {activity_description};")
        else:
            # Incoming message to local host (from remote)
            plantuml_output.append(f"#blue:Remote Host sends {activity_description};")

    plantuml_output.append("stop")
    plantuml_output.append("@enduml")
    return "\n".join(plantuml_output)

def generate_state_diagram_plantuml(parsed_logs):
    plantuml_output = []
    unique_participants = set()
    for log in parsed_logs:
        unique_participants.add(log['source'])
        unique_participants.add(log['destination'])

    for participant in sorted(list(unique_participants)):
        plantuml_output.append(f"@startuml State Diagram for {participant.replace(':', '_').replace('.', '_')}")
        plantuml_output.append("skinparam monochrome true")
        plantuml_output.append("[*] --> Idle")

        current_state = "Idle"
        for i, log in enumerate(parsed_logs):
            if log['source'] == participant:
                # Participant is sending a message
                event = f"Sends {log['type']}"
                new_state = f"Sent_{log['type']}_{i}"
                plantuml_output.append(f"{current_state} --> {new_state} : {event}")
                current_state = new_state
            elif log['destination'] == participant:
                # Participant is receiving a message
                event = f"Receives {log['type']}"
                new_state = f"Received_{log['type']}_{i}"
                plantuml_output.append(f"{current_state} --> {new_state} : {event}")
                current_state = new_state
        plantuml_output.append(f"{current_state} --> [*]")
        plantuml_output.append("@enduml")
        plantuml_output.append("\n") # Separator between diagrams

    return "\n".join(plantuml_output)

def render_plantuml_to_image(plantuml_syntax, diagram_name):
    # Create a temporary .puml file
    fd, path = tempfile.mkstemp(suffix=".puml")
    with os.fdopen(fd, 'w') as tmp:
        tmp.write(plantuml_syntax)

    # Attempt to render using plantuml.jar
    # IMPORTANT: User needs to have Java and plantuml.jar installed and accessible.
    # You might need to adjust the command if plantuml.jar is not in your PATH
    # or if you want a different output format (e.g., -tsvg for SVG).
    output_path = path.replace(".puml", ".png")
    # Assuming plantuml.jar is in the current directory or PATH
    command = f"java -jar plantuml.jar -o \"{os.path.dirname(output_path)}\" \"{path}\""
    
    print(f"Attempting to render {diagram_name} to {output_path}")
    print(f"Executing command: {command}")
    
    # Execute the command using the provided tool
    # Note: The actual execution and its output will be handled by the tool.
    # This function will return the expected output path.
    # The temporary .puml file will remain for inspection if needed.
    
    # You would typically call default_api.run_shell_command here.
    # For now, I will just print the command and the expected output path.
    # The actual execution will be done in the main block.
    
    return output_path, path # Return both image path and temp puml path

def generate_ascii_sequence_diagram(parsed_logs):
    output = []
    output.append("ASCII Sequence Diagram:")
    output.append("-----------------------")

    unique_participants = sorted(list(set([log['source'] for log in parsed_logs] + [log['destination'] for log in parsed_logs])))
    participant_cols = {p: i * 15 for i, p in enumerate(unique_participants)}
    participant_names = {p: p.split(':')[-1] for p in unique_participants} # Use port or last part of address

    # Print participant headers
    header_line = ""
    for p in unique_participants:
        header_line += f"{participant_names[p]:<15}"
    output.append(header_line)
    output.append("-" * len(header_line))

    for log in parsed_logs:
        sender = log['source']
        receiver = log['destination']
        message_type = log['type']

        sender_col = participant_cols[sender]
        receiver_col = participant_cols[receiver]

        line = [' ' for _ in range(max(sender_col, receiver_col) + 15)]

        # Draw participants' lifelines
        for col in participant_cols.values():
            if col < len(line):
                line[col] = '|'

        # Draw message arrow
        if sender_col < receiver_col:
            # Sender -> Receiver
            for i in range(sender_col + 1, receiver_col):
                line[i] = '-'
            line[receiver_col] = '>'
            line[sender_col] = '|'
            message_start = sender_col + 1
        else:
            # Sender <- Receiver
            for i in range(receiver_col + 1, sender_col):
                line[i] = '-'
            line[receiver_col] = '<'
            line[sender_col] = '|'
            message_start = receiver_col + 1

        message_text = f"[{message_type}]"
        for i, char in enumerate(message_text):
            if message_start + i < len(line):
                line[message_start + i] = char

        output.append("".join(line))

    output.append("-----------------------")
    return "\n".join(output)

def generate_ascii_activity_flow(parsed_logs):
    output = []
    output.append("ASCII Activity Flow:")
    output.append("---------------------")

    for i, log in enumerate(parsed_logs):
        direction = "OUT" if 'localhost' in log['source'] else "IN"
        output.append(f"{i:03d}: {direction} {log['type']} ({log['source']} -> {log['destination']})")

    output.append("---------------------")
    return "\n".join(output)

def generate_ascii_state_flow(parsed_logs):
    output = []
    output.append("ASCII State Flow (per participant):")
    output.append("-----------------------------------")

    unique_participants = sorted(list(set([log['source'] for log in parsed_logs] + [log['destination'] for log in parsed_logs])))

    for participant in unique_participants:
        output.append(f"\nParticipant: {participant}")
        output.append(f"  Initial State: Idle")
        current_state = "Idle"

        for i, log in enumerate(parsed_logs):
            if log['source'] == participant:
                event = f"Sends {log['type']}"
                new_state = f"Sent_{log['type']}_{i}"
                output.append(f"  {current_state} --({event})--> {new_state}")
                current_state = new_state
            elif log['destination'] == participant:
                event = f"Receives {log['type']}"
                new_state = f"Received_{log['type']}_{i}"
                output.append(f"  {current_state} --({event})--> {new_state}")
                current_state = new_state
        output.append(f"  {current_state} --(End)--> Final")

    output.append("-----------------------------------")
    return "\n".join(output)

import sys

if __name__ == "__main__":
    if len(sys.argv) > 1:
        log_file = sys.argv[1]
    else:
        log_file = 'p2p_signage_dart/test_log.txt'
    parsed = parse_log_file(log_file)
    print_wireshark_style(parsed)

    print("\n" + "=" * 140)
    print(generate_ascii_sequence_diagram(parsed))
    print("=" * 140)

    print("\n" + "=" * 140)
    print(generate_ascii_activity_flow(parsed))
    print("=" * 140)

    print("\n" + "=" * 140)
    print(generate_ascii_state_flow(parsed))
    print("=" * 140)
