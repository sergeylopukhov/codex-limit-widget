# Codex Limit Widget

<p align="center">
  <a href="README.md">English</a> · <a href="README.ru.md"><strong>Русский</strong></a>
</p>

<div align="center">
  <img src="assets/screenshots/readme/beige-large.png" width="520" alt="Большой виджет Codex Limit Widget в бежевом оформлении">

  <p>
    Приложение для строки меню macOS и виджет рабочего стола, чтобы видеть лимиты Codex.
  </p>

  <p>
    <a href="https://github.com/sergeylopukhov/codex-limit-widget/releases/latest"><img alt="Скачать последнюю версию" src="https://img.shields.io/badge/download-latest_release-222222?style=for-the-badge"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-777777?style=for-the-badge">
    <img alt="WidgetKit" src="https://img.shields.io/badge/WidgetKit-enabled-6f8f5f?style=for-the-badge">
  </p>
</div>

Codex Limit Widget — приложение для строки меню macOS и виджет рабочего стола. Оно показывает остаток 5-часового и недельного лимитов Codex, время сброса, план и статистику использования. Codex Desktop держать открытым не нужно: приложение обновляет данные в фоне и передаёт их виджету macOS.

## Что показывает

- Остаток 5-часового и недельного лимитов.
- Время сброса каждого лимита.
- Текущий план Codex.
- Статистику использования: токены, день с наибольшим расходом, последний день, серию дней и самый долгий запрос.
- Компактный или подробный индикатор в строке меню.
- Виджет macOS в размерах Small, Medium и Large.
- Два оформления: Dark и Beige.

## Установка

1. Скачайте последнюю версию `.dmg` в [GitHub Releases](https://github.com/sergeylopukhov/codex-limit-widget/releases/latest).
2. Откройте файл и перетащите `Codex Limit Widget.app` в `Applications`.
3. Запустите приложение.

Требования:

- macOS 14 или новее.
- Установленный и авторизованный Codex CLI.

## Как добавить виджет

Откройте галерею виджетов macOS, найдите `Codex Limit Widget` и выберите размер: Small, Medium или Large.

Оформление меняется в настройках приложения. Выберите `Dark` или `Beige`; уже добавленные виджеты обновятся, пока приложение запущено.

## Строка меню

Индикатор в строке меню может показывать подробные лимиты или компактный процент. Нажмите на него, чтобы открыть окно с лимитами, временем сброса, свежестью данных и настройками.

<table>
  <tr>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/popover-window-beige.png" width="100%" alt="Окно строки меню в бежевом оформлении"><br>
      <sub>Beige</sub>
    </td>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/popover-window-dark.png" width="100%" alt="Окно строки меню в тёмном оформлении"><br>
      <sub>Dark</sub>
    </td>
  </tr>
</table>

## Виджеты

<table>
  <tr>
    <td width="40%" align="center">
      <img src="assets/screenshots/readme/beige-large.png" width="100%" alt="Большой виджет Codex Limit Widget в бежевом оформлении"><br>
      <sub>Large</sub>
    </td>
    <td width="38%" align="center">
      <img src="assets/screenshots/readme/beige-medium.png" width="100%" alt="Средний виджет Codex Limit Widget в бежевом оформлении"><br>
      <sub>Medium</sub>
    </td>
    <td width="22%" align="center">
      <img src="assets/screenshots/readme/beige-small.png" width="100%" alt="Маленький виджет Codex Limit Widget в бежевом оформлении"><br>
      <sub>Small</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td width="40%" align="center">
      <img src="assets/screenshots/readme/dark-large.png" width="100%" alt="Большой виджет Codex Limit Widget в тёмном оформлении"><br>
      <sub>Large</sub>
    </td>
    <td width="38%" align="center">
      <img src="assets/screenshots/readme/dark-medium.png" width="100%" alt="Средний виджет Codex Limit Widget в тёмном оформлении"><br>
      <sub>Medium</sub>
    </td>
    <td width="22%" align="center">
      <img src="assets/screenshots/readme/dark-small.png" width="100%" alt="Маленький виджет Codex Limit Widget в тёмном оформлении"><br>
      <sub>Small</sub>
    </td>
  </tr>
</table>

## Настройки

В настройках можно выбрать оформление окна, режим строки меню и источник процента.

<table>
  <tr>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/settings-window-beige.png" width="100%" alt="Окно настроек с выбранным бежевым оформлением"><br>
      <sub>Beige</sub>
    </td>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/settings-window-dark.png" width="100%" alt="Окно настроек с выбранным тёмным оформлением"><br>
      <sub>Dark</sub>
    </td>
  </tr>
</table>

## Приватность

Codex Limit Widget читает данные из локальной сессии Codex CLI и хранит небольшой локальный снимок для виджетов. На свой сервер приложение ничего не отправляет.

## Удаление

Завершите Codex Limit Widget и удалите приложение из папки `Applications`.

Если после удаления виджет всё ещё виден в галерее, перезагрузите Mac и удалите другие локальные копии `Codex Limit Widget.app`.
