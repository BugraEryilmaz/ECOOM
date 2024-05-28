import sys

# Check if a file path is provided as a command-line argument
if len(sys.argv) < 3:
    print("Please provide a file path as a command-line argument.")
    sys.exit(1)

file_path = sys.argv[1]
output_path = sys.argv[2]

with open(output_path, 'w') as ofile:
    with open(file_path, 'r') as file:
        lines = file.readlines()
        for line in lines:
            if line.startswith('$$'):
                fields = line.split(' ')
                fields = [field for field in fields if field != '']
                start = int(fields[1]) + 1
                end = int(fields[2])
                # print(f"Start: {start}, End: {end}")
                for i in range(start, end):
                    ofile.write(f"R\t{i}\t{i}\t1\n")
            else:
                ofile.write(line)
