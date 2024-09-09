#!/bin/bash

# Identificar o sistema operacional
OS="$(uname)"

# Verificar os softwares instalados e suas versões
if [ "$OS" = "Linux" ]; then
    echo "Nome do Software,Versão"
    dpkg-query -W -f='${binary:Package},${Version}\n'
elif [ "$OS" = "Darwin" ]; then
    echo "Nome do Software,Versão"
    brew list --versions | while read cask; do echo $cask | awk '{print $1 "," $2}'; done
else
    echo "Sistema Operacional não suportado."
fi
