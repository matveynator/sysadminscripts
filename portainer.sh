#!/bin/bash

# Обновление списка пакетов
sudo apt update

# Установка необходимых пакетов для использования репозитория по HTTPS
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common

# Добавление официального ключа GPG Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Добавление официального репозитория Docker
echo "deb [signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Обновление списка пакетов после добавления репозитория Docker
sudo apt update

# Установка Docker Engine
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Добавление текущего пользователя в группу docker для выполнения команд без sudo
sudo usermod -aG docker $USER

# Установка Portainer
sudo docker volume create portainer_data
sudo docker run -d -p 9000:9000 -p 8000:8000 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

echo "Установка завершена. Docker и Portainer установлены на сервере Debian."
