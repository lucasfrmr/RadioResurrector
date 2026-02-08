# Docker Setup Instructions

To run the project using Docker, follow these instructions:

1. Make sure you have Docker installed on your machine.
2. Clone the repository:
   ```bash
   git clone https://github.com/lucasfrmr/RadioResurrector.git
   ```
3. Navigate to the project folder:
   ```bash
   cd RadioResurrector
   ```
4. Build the Docker image:
   ```bash
   docker build -t radioresurrector .
   ```
5. Run the Docker container:
   ```bash
   docker run -d -p 8080:8080 radioresurrector
   ```

Alternative method for Raspberry Pi users:

## Raspberry Pi Instructions

1. Ensure your Raspberry Pi is running the latest version of Raspberry Pi OS.
2. Install the necessary dependencies:
   ```bash
   sudo apt install package_name
   ```
3. Follow the existing instructions to set up the environment.
