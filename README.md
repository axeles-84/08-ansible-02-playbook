Установка ClickHouse и Vector через Ansible
📋 Содержание
Общее описание

Требования

Структура проекта

Инвентарь

Переменные

Play 1: Install ClickHouse

Play 2: Install Vector

Шаблон конфигурации Vector

Запуск Playbook

Проверка результата

Диагностика проблем

Совместимость версий

Ключевые правила


ansible-project/
├── site.yml                       # Основной playbook (2 play)
├── inventory/
│   └── prod.yml                   # Инвентарь
├── group_vars/
│   └── clickhouse.yml             # Переменные
└── templates/
    └── vector.toml.j2             # Jinja2-шаблон конфига Vector