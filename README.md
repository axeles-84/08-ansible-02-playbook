# 🚀 Установка ClickHouse и Vector через Ansible

[![Ansible](https://img.shields.io/badge/Ansible-%3E%3D2.13-blue)](https://docs.ansible.com/)
[![CentOS](https://img.shields.io/badge/CentOS-7-green)](https://www.centos.org/)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-22.3.3.44-yellow)](https://clickhouse.com/)
[![Vector](https://img.shields.io/badge/Vector-0.31.0-purple)](https://vector.dev/)

Ansible-плейбук для автоматической установки и настройки **ClickHouse** и **Vector** на серверы под управлением **CentOS 7**.

---

## 📖 Содержание

- [Общее описание](#-общее-описание)
- [Требования](#-требования)
- [Структура проекта](#-структура-проекта)
- [Инвентарь](#-инвентарь)
- [Переменные](#-переменные)
- [Play 1: Install ClickHouse](#-play-1-install-clickhouse)
- [Play 2: Install Vector](#-play-2-install-vector)
- [Шаблон конфигурации Vector](#-шаблон-конфигурации-vector)
- [Запуск Playbook](#-запуск-playbook)
- [Проверка результата](#-проверка-результата)
- [Диагностика проблем](#-диагностика-проблем)
- [Совместимость версий](#-совместимость-версий)
- [Ключевые правила](#-ключевые-правила)

---

##Общее описание

Playbook предназначен для развёртывания стека аналитики логов и состоит из **двух последовательных play**:

1. **Install ClickHouse** — скачивание RPM-пакетов, установка СУБД, запуск сервиса, создание базы `logs` и таблицы `logs_table`.
2. **Install Vector** — скачивание RPM-пакета, установка агента и деплой конфигурации из Jinja2-шаблона.

**Целевые хосты:** группа `clickhouse` из инвентаря.
**Пользователь:** `root` (через `become`).

---

## 📋 Требования

| Компонент | Версия | Назначение |
|-----------|--------|-----------|
| Ansible | ≥ 2.13 | Управляющий узел |
| CentOS | 7 | Целевая ОС (GLIBC 2.17) |
| ClickHouse | `22.3.3.44` (LTS) | СУБД |
| Vector | `0.31.0` | Агент логов |


### Требования к ВМ

- 2 vCPU,  4 ГБ RAM** 
- Открытые порты: `22` (SSH), `8123` (ClickHouse HTTP), `9000` (ClickHouse native)
- Пользователь с `sudo` без пароля

---

## 📁 Структура проекта

```
ansible-project/
├── site.yml                       # Основной playbook (2 play)
├── inventory/
│   └── prod.yml                   # Инвентарь
├── group_vars/
│   └── clickhouse/vars.yml             # Переменные
└── templates/
    └── vector.toml.j2             # Jinja2-шаблон конфига Vector
```

---

## 🌐 Инвентарь

**Файл:** `inventory/prod.yml`

```yaml
clickhouse:
  hosts:
    clickhouse-01:
      ansible_host: ip хоста
      ansible_user: centos

     
| Параметр | Описание |
|----------|----------|
| `ansible_host` | IP-адрес или доменное имя ВМ |
| `ansible_user` | Пользователь для SSH |

```

---

## ⚙️ Переменные

**Файл:** `group_vars/clickhouse/vars.yml`

```yaml
---
lickhouse_version: "22.3.3.44"
clickhouse_packages:
  - clickhouse-client
  - clickhouse-server
  - clickhouse-common-static
vector_version: "0.31.0"
vector_config_dir: "{{ ansible_user_dir }}/vector_config"
vector_config:

```

| Переменная | Назначение |
|-----------|-----------|
| `clickhouse_version` | Версия ClickHouse |
| `clickhouse_database` | Имя базы для логов |
| `clickhouse_table` | Имя таблицы для логов |
| `vector_version` | Версия Vector |
| `vector_config_dir` | Директория конфигов |


---

## 🗄️ Play 1: Install ClickHouse

### Параметры play

```yaml
- name: Install Clickhouse
  hosts: clickhouse
  become: true
  become_user: root
```

### Handlers

| Handler | Назначение |
|---------|-----------|
| `Start clickhouse service` | Перезапуск `clickhouse-server` |
| `Ensure systemd is in a clean state` | `systemctl daemon-reexec` |

### Задачи

#### 1️⃣ Скачивание RPM-пакетов

```yaml
- name: Get clickhouse distrib
  ansible.builtin.get_url:
    url: "https://packages.clickhouse.com/rpm/lts/{{ item }}-{{ clickhouse_version }}.noarch.rpm"
    dest: "./{{ item }}-{{ clickhouse_version }}.rpm"
  with_items:
    - clickhouse-client
    - clickhouse-server

- name: Get clickhouse distrib
  ansible.builtin.get_url:
    url: "https://packages.clickhouse.com/rpm/lts/clickhouse-common-static-{{ clickhouse_version }}.x86_64.rpm"
    dest: "./clickhouse-common-static-{{ clickhouse_version }}.rpm"
```

#### 2️⃣ Установка пакетов

```yaml
- name: Install clickhouse packages
  ansible.builtin.yum:
    name:
      - clickhouse-client-{{ clickhouse_version }}.rpm
      - clickhouse-server-{{ clickhouse_version }}.rpm
      - clickhouse-common-static-{{ clickhouse_version }}.rpm
  notify: Start clickhouse service
```

#### 3️⃣ Запуск сервиса

```yaml
- name: Ensure ClickHouse is running
  ansible.builtin.systemd:
    name: clickhouse-server
    state: restarted
    enabled: yes
    daemon_reload: yes
  async: 300
  poll: 5
```

#### 4️⃣ Ожидание готовности

```yaml
- name: Wait until ClickHouse responds to queries
  ansible.builtin.command: "clickhouse-client -q 'SELECT 1'"
  register: ch_ready
  until: ch_ready.rc == 0
  retries: 30
  delay: 10
  changed_when: false
  failed_when: false
```

#### 5️⃣ Создание базы и таблицы

```yaml
- name: Create ClickHouse database
  ansible.builtin.command: "clickhouse-client -q 'CREATE DATABASE IF NOT EXISTS logs;'"
  register: create_db
  failed_when: create_db.rc != 0 and create_db.rc != 82
  changed_when: create_db.rc == 0

- name: Create ClickHouse table
  ansible.builtin.command: >
    clickhouse-client -q "CREATE TABLE IF NOT EXISTS logs.logs_table
    (timestamp String, message String)
    ENGINE = MergeTree() ORDER BY timestamp;"
```

---

## 📦 Play 2: Install Vector

### Параметры play

```yaml
- name: Install vector
  hosts: clickhouse
  become: true
  become_user: root
```

### Handlers

```yaml
handlers:
  - name: Restart vector service
    ansible.builtin.service:
      name: vector
      state: restarted
```

### Задачи

#### 1️⃣ Скачивание Vector

```yaml
- name: Get vector distrib
  ansible.builtin.get_url:
    url: "https://yum.vector.dev/stable/vector-0/x86_64/vector-{{ vector_version }}-1.x86_64.rpm"
    dest: "./vector-{{ vector_version }}.rpm"
    mode: "0644"
  notify: Restart vector service
```

#### 2️⃣ Установка

```yaml
- name: Install vector packages
  ansible.builtin.yum:
    name:
      - vector-{{ vector_version }}.rpm
    disable_gpg_check: true
```

#### 3️⃣ Применение handlers

```yaml
- name: Flush handlers to restart vector
  ansible.builtin.meta: flush_handlers
```

#### 4️⃣ Деплой конфигурации

```yaml
- name: Deploy Vector configuration from template
  ansible.builtin.template:
    src: vector.toml.j2
    dest: /etc/vector/vector.toml
    owner: vector
    group: vector
    mode: '0644'
    validate: /usr/bin/vector validate --config-toml %s
  notify: Restart vector service
```

---

## 📄 Шаблон конфигурации Vector

**Файл:** `templates/vector.toml.j2`

```jinja2
data_dir = "/var/lib/vector/"

[api]
enabled = true
address = "127.0.0.1:8686"

[sources.demo_logs]
type = "demo_logs"
format = "json"
interval = 1

[sinks.clickhouse]
type = "clickhouse"
inputs = ["demo_logs"]
endpoint = "http://localhost:8123"
database = "logs"
table = "logs_table"
skip_unknown_fields = true
auth.strategy = "basic"
auth.user = "default"
auth.password = ""

[sinks.stdout]
type = "console"
inputs = ["demo_logs"]
encoding.codec = "json"

```

### Ключевые параметры

| Параметр | Значение | Пояснение |
|----------|----------|-----------|
| `endpoint` | `http://localhost:8123` |
| `skip_unknown_fields` | `true` | Пропуск лишних полей |
| `auth.strategy` | `basic` | Basic Auth для ClickHouse |
| `[api]` | `127.0.0.1:8686` | API для health-check |

---

## 🚀 Запуск Playbook

### Полный запуск

```bash
ansible-playbook -i inventory/prod.yml site.yml
```

### Проверка синтаксиса

```bash
ansible-playbook -i inventory/prod.yml site.yml --syntax-check
```

### Пробный прогон

```bash
ansible-playbook -i inventory/prod.yml site.yml --check --diff
```

### Только ClickHouse

```bash
ansible-playbook -i inventory/prod.yml site.yml --start-at-task="Get clickhouse distrib"
```

### Только Vector

```bash
ansible-playbook -i inventory/prod.yml site.yml --start-at-task="Get vector distrib"
```

---

## ✅ Проверка результата

### На хосте

```bash
# 1. Статус сервисов
sudo systemctl status clickhouse-server
sudo systemctl status vector

# 2. ClickHouse работает?
curl -s http://localhost:8123/ping
# Ok.

clickhouse-client -q "SELECT version();"

# 3. База и таблица созданы?
clickhouse-client -q "SHOW DATABASES;"
clickhouse-client -q "SHOW TABLES FROM logs;"
clickhouse-client -q "DESCRIBE logs.logs_table;"
# timestamp  String
# message    String

# 4. Данные идут?
clickhouse-client -q "SELECT count() FROM logs.logs_table;"
sleep 15
clickhouse-client -q "SELECT count() FROM logs.logs_table;"
# Счётчик растёт

# 5. Логи Vector
sudo journalctl -u vector -n 20 --no-pager

# 6. API Vector
curl -s http://localhost:8686/health
```
---



<div align="center">
