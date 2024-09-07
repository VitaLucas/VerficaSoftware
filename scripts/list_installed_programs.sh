#!/bin/bash
if command -v brew &> /dev/null; then
  brew list --formula
elif command -v dpkg &> /dev/null; then
  dpkg --list
else
  echo "Não foi possível determinar o gerenciador de pacotes."
fi