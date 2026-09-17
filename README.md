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

## 📝 Общее описание

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
| Python | ≥ 3.6 | На управляемом хосте |

### Требования к ВМ

- 2 vCPU, **минимум 2 ГБ RAM** (ClickHouse требователен к памяти)
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
│   └── clickhouse.yml             # Переменные
└── templates/
    └── vector.toml.j2             # Jinja2-шаблон конфига Vector
```

---

## 🌐 Инвентарь

**Файл:** `inventory/prod.yml`

```yaml
all:
  children:
    clickhouse:
      hosts:
        clickhouse-01:
          ansible_host: 62.84.113.211
          ansible_user: centos
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

| Параметр | Описание |
|----------|----------|
| `ansible_host` | IP-адрес или доменное имя ВМ |
| `ansible_user` | Пользователь для SSH |
| `ansible_ssh_private_key_file` | Путь к приватному ключу |

---

## ⚙️ Переменные

**Файл:** `group_vars/clickhouse.yml`

```yaml
---
# ClickHouse
clickhouse_version: "22.3.3.44"
clickhouse_packages:
  - clickhouse-client
  - clickhouse-server
  - clickhouse-common-static
clickhouse_database: logs
clickhouse_table: logs_table

# Vector
vector_version: "0.31.0"
vector_config_dir: "{{ ansible_user_dir }}/vector_config"
vector_config_path: "/etc/vector/vector.toml"
vector_log_interval: 1

# Подключение Vector → ClickHouse
clickhouse_host: localhost
clickhouse_user: default
clickhouse_password: ""
```

| Переменная | Назначение |
|-----------|-----------|
| `clickhouse_version` | Версия ClickHouse |
| `clickhouse_database` | Имя базы для логов |
| `clickhouse_table` | Имя таблицы для логов |
| `vector_version` | Версия Vector |
| `vector_config_dir` | Директория конфигов |
| `vector_config_path` | Полный путь к конфигу |
| `vector_log_interval` | Интервал demo-логов (сек) |
| `clickhouse_host` | Адрес ClickHouse для Vector |

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

> ⚠️ **Важно:** Тип `timestamp` — **`String`**, а не `DateTime`. Vector отправляет ISO8601 с наносекундами, который `DateTime` не парсит.

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
# {{ ansible_managed }}
data_dir = "/var/lib/vector/"

[api]
enabled = true
address = "127.0.0.1:8686"

[sources.demo_logs]
type = "demo_logs"
format = "json"
interval = {{ vector_log_interval }}

[sinks.clickhouse]
type = "clickhouse"
inputs = ["demo_logs"]
endpoint = "http://{{ clickhouse_host }}:8123"
database = "{{ clickhouse_database }}"
table = "{{ clickhouse_table }}"
skip_unknown_fields = true
auth.strategy = "basic"
auth.user = "{{ clickhouse_user }}"
auth.password = "{{ clickhouse_password }}"

[sinks.stdout]
type = "console"
inputs = ["demo_logs"]
encoding.codec = "json"
```

### Ключевые параметры

| Параметр | Значение | Пояснение |
|----------|----------|-----------|
| `endpoint` | `http://localhost:8123` | **HTTP-порт**, не 9000 |
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

### Идемпотентность

Повторный запуск должен дать `changed=0`:

```bash
ansible-playbook -i inventory/prod.yml site.yml
# clickhouse-01 : ok=X  changed=0  failed=0
```

---

## 🔧 Диагностика проблем

### ClickHouse

| Симптом | Причина | Решение |
|---------|---------|---------|
| `Connection refused (9000)` | Сервис не готов | `wait_for` + `until SELECT 1` |
| `Job timed out` | Первый старт долгий | `async: 300` |
| Сервис падает | Мало RAM | Увеличить ВМ до 4 ГБ |
| `Permissions denied /var/lib/clickhouse` | Неверный владелец | `chown -R clickhouse:clickhouse /var/lib/clickhouse` |

### Vector

| Симптом | Причина | Решение |
|---------|---------|---------|
| `Unit vector.service not found` | Юнит не создан | Создать `/etc/systemd/system/vector.service` |
| `203/EXEC` | Не найден бинарник | Проверить `/usr/bin/vector` |
| `Job failed` | Ошибка конфига | `vector validate --config-toml /etc/vector/vector.toml` |
| `Permission denied /var/lib/vector` | Нет прав | `chown -R vector:vector /var/lib/vector` |

### Данные в ClickHouse

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `Unknown field` | Лишние поля | `skip_unknown_fields = true` |
| `Table doesn't exist` | Таблицы нет | Создать `logs.logs_table` |
| `400 Bad Request` | Формат `timestamp` | Использовать `String` вместо `DateTime` |
| `Connection refused` | ClickHouse не запущен | `systemctl start clickhouse-server` |
| `Authentication failed` | Неверные креды | Проверить `auth.user` / `auth.password` |

---

## 🔄 Совместимость версий

| Компонент | Версия | GLIBC | CentOS 7 |
|-----------|--------|-------|----------|
| ClickHouse | 22.3.3.44 (LTS) | 2.17 | ✅ |
| Vector | 0.31.0 | 2.17 | ✅ |
| Vector | 0.34.2 | 2.17 | ✅ Последняя совместимая |
| Vector | 0.35.0+ | 2.28+ | ❌ Не работает |

**Проверка GLIBC:**

```bash
ldd --version | head -1
# ldd (GNU libc) 2.17
```

---

## 📐 Ключевые правила

### Отступы YAML

| Уровень | Отступ |
|---------|--------|
| Play | 0 |
| `hosts:`, `become:`, `tasks:`, `handlers:` | 2 |
| Задача `- name:` | 4 |
| Модуль `ansible.builtin.X:` | 6 |
| Параметр модуля | 8 |
| **Директивы задачи** (`async`, `poll`, `notify`, `when`, `register`) | **6** |

### Идемпотентность

- Использовать `CREATE ... IF NOT EXISTS`
- `CREATE DATABASE` → `failed_when: rc != 0 and rc != 82` (82 = «уже существует»)
- `changed_when: false` для проверочных команд

### `flush_handlers`

Вызывается **после** уведомляющих задач и **перед** задачами, которые зависят от перезапуска сервиса.

---

## 📚 Ссылки

- [Ansible Documentation](https://docs.ansible.com/)
- [ClickHouse Docs](https://clickhouse.com/docs/)
- [Vector Docs](https://vector.dev/docs/)
- [Ansible systemd module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/systemd_module.html)
- [Ansible yum module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/yum_module.html)

---

## 📜 Лицензия

Проект распространяется под лицензией **MIT**. Подробнее см. в файле [LICENSE](LICENSE).

---

## 🕒 История версий документа

| Версия | Дата | Изменения |
|--------|------|-----------|
| 1.0 | 2026-09-17 | Первая версия документации |

---

<div align="center">
