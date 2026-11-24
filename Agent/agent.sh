#!/bin/bash

# Simple Obsidian Agent
# This would connect to Ollama and process vault files

echo "Starting Obsidian Agent..."
echo "Ollama Status: $(curl -s http://localhost:11434/api/version)"
echo "Agent ready!"
