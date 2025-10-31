# --------------------------------------------------------------------------------
# Provider Configuration
# --------------------------------------------------------------------------------

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --------------------------------------------------------------------------------
# 1. VPC Network and Subnet
# --------------------------------------------------------------------------------

resource "google_compute_network" "llm_vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "llm_subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.llm_vpc.self_link
}

# --------------------------------------------------------------------------------
# 2. Firewall Rules
# --------------------------------------------------------------------------------

# Rule 1: Allow SSH (TCP 22) only from the specific source IP defined in variables
resource "google_compute_firewall" "allow_ssh_specific_ip" {
  name    = "allow-ssh-from-admin-ip"
  network = google_compute_network.llm_vpc.self_link
  target_tags = ["llm-instance"] # Applies only to VMs with this tag
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.ssh_source_ip]
  description   = "Allow SSH from a specific administrative IP only."
}

# Rule 2: Allow all outbound traffic (default, but good to explicitly state)
resource "google_compute_firewall" "allow_egress" {
  name    = "allow-all-egress"
  network = google_compute_network.llm_vpc.self_link
  direction = "EGRESS"
  
  allow {
    protocol = "all"
  }
  
  destination_ranges = ["0.0.0.0/0"]
}

# --------------------------------------------------------------------------------
# 3. Compute Engine VM Instance for LLM Deployment
# --------------------------------------------------------------------------------

resource "google_compute_instance" "llm_vm" {
  name         = "tinylama-vm"
  machine_type = "n2-standard-8" # 8 vCPUs, 32GB RAM - Good general ML starting point

  # NOTE: For serious LLM serving, you should use a machine type with a GPU.
  # Example for 1x L4 GPU (Check region availability and quotas!):
  /*
  machine_type = "g2-standard-8" 
  guest_accelerator {
    type  = "nvidia-l4"
    count = 1
  }
  */
  
  zone         = var.zone
  tags         = ["llm-instance", "ssh"]

  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11" # Using a standard Debian image
      size  = 100 # Large disk size for model weights and logs
      type  = "pd-ssd" # Use SSD for better I/O performance
    }
  }

  # Network Interface (must use the custom subnet)
  network_interface {
    subnetwork = google_compute_subnetwork.llm_subnet.self_link
    # Assign a public IP to access the instance
    access_config {
      # Empty block assigns ephemeral public IP
    }
  }
  
  # Scopes required for downloading public models and interacting with cloud services
  service_account {
    scopes = ["cloud-platform"]
  }

  # Startup script to install dependencies and run the model on boot
  metadata_startup_script = <<-EOF
    #!/bin/bash
    
    # 1. Update and install basic tools
    apt update && apt install -y python3-pip git
    
    # 2. Install Hugging Face and PyTorch dependencies
    # Note: This is a CPU-only setup. For GPU, you'd need the CUDA-enabled PyTorch build.
    pip3 install torch transformers accelerate
    
    # 3. Clone the TinyLlama model weights and prepare a script (Conceptual setup)
    # The TinyLlama-1.1B-Chat-v1.0 model is relatively small (~2GB) and can run on CPU/RAM,
    # but performance will be slow compared to GPU.
    
    MODEL_DIR="/opt/tinylama"
    mkdir -p $MODEL_DIR
    
    cat > $MODEL_DIR/run_model.py << EOL
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    import sys
    
    print("Starting TinyLlama model load...")
    
    try:
        # Load the model and tokenizer from Hugging Face Hub
        tokenizer = AutoTokenizer.from_pretrained("TinyLlama/TinyLlama-1.1B-Chat-v1.0")
        model = AutoModelForCausalLM.from_pretrained("TinyLlama/TinyLlama-1.1B-Chat-v1.0")
        
        # Move model to CPU (or GPU if configured)
        device = "cuda" if torch.cuda.is_available() else "cpu"
        model.to(device)
        print(f"Model loaded successfully on {device}!")
        
        # Simple inference example (optional, just for verification)
        prompt = "Explain why large language models are powerful in one sentence."
        inputs = tokenizer(prompt, return_tensors="pt").to(device)
        
        outputs = model.generate(
            **inputs, 
            max_new_tokens=50, 
            do_sample=True, 
            temperature=0.7, 
            pad_token_id=tokenizer.eos_token_id
        )
        
        response = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        # Save the result to a log file
        with open("/var/log/tinylama_startup_output.log", "w") as f:
            f.write("--- Model Setup Complete ---\n")
            f.write(f"Device used: {device}\n")
            f.write(f"Prompt: {prompt}\n")
            f.write(f"Response: {response}\n")
        
        print("Startup script finished successfully.")
        
    except Exception as e:
        with open("/var/log/tinylama_startup_error.log", "w") as f:
            f.write(f"Error during model setup: {e}\n")
        sys.exit(1)
    
    EOL
    
    # 4. Execute the Python script
    python3 $MODEL_DIR/run_model.py & 
    
    # In a real deployment, you would start a proper serving framework here (e.g., TGI, vLLM, or FastAPI app)
    # and expose the relevant port via another firewall rule.
  EOF
}

# --------------------------------------------------------------------------------
# 4. Output the created VM information
# --------------------------------------------------------------------------------

output "instance_name" {
  description = "The name of the created Compute Engine instance."
  value       = google_compute_instance.llm_vm.name
}

output "instance_public_ip" {
  description = "The ephemeral public IP address of the instance (use this to SSH)."
  value       = google_compute_instance.llm_vm.network_interface[0].access_config[0].nat_ip
}
