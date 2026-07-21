# Codex Limit Widget

<p align="center">
  <a href="README.md">English</a> · <a href="README.ru.md"><strong>Русский</strong></a>
</p>

<div align="center">
  <img src="assets/screenshots/readme/beige-large.png" width="520" alt="Большой виджет Codex Limit Widget в бежевом оформлении">

  <p>
    Приложение для строки меню macOS и виджет рабочего стола, чтобы видеть лимиты Codex.
  </p>

  <p>
    <a href="https://github.com/sergeylopukhov/codex-limit-widget/releases/latest"><img alt="Скачать последнюю версию" src="https://img.shields.io/badge/download-latest_release-222222?style=for-the-badge"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-777777?style=for-the-badge">
    <img alt="WidgetKit" src="https://img.shields.io/badge/WidgetKit-enabled-6f8f5f?style=for-the-badge">
  </p>
</div>

Codex Limit Widget показывает в строке меню macOS и на рабочем столе те лимиты, которые Codex вернул для вашей учётной записи. Пользователи только с недельным лимитом не увидят подпись 5h и пустое место под отсутствующие данные. Если 5-часовой лимит доступен, на экране будут оба значения. Время сброса, план и статистика использования остаются под рукой без запущенного Codex Desktop.

Пока приложение запущено, локальные данные обновляются раз в минуту. Последний снимок передаётся в WidgetKit.

## Что показывает

- Все доступные лимиты: недельный и 5-часовой, если Codex его возвращает.
- Дату и время сброса каждого доступного лимита.
- Текущий план Codex.
- Статистику использования: токены, день с наибольшим расходом, последний день, серию дней и самый долгий запрос.
- Компактный или подробный индикатор в строке меню.
- Виджет macOS в размерах Small, Medium и Large.
- Два оформления: Dark и Beige.
- Уведомление и кнопку `Update now`, когда выходит новая версия.

## Установка

1. Скачайте последнюю версию `.dmg` в [GitHub Releases](https://github.com/sergeylopukhov/codex-limit-widget/releases/latest).
2. Откройте файл и перетащите `Codex Limit Widget.app` в `Applications`.
3. Запустите приложение.

Начиная с версии 1.1.8 следующие обновления устанавливаются из самого приложения.

Требования:

- macOS 14 или новее.
- Установленный и авторизованный Codex CLI.

## Как добавить виджет

Откройте галерею виджетов macOS, найдите `Codex Limit Widget` и выберите размер: Small, Medium или Large.

Оформление меняется в настройках приложения. Выберите `Dark` или `Beige`; уже добавленные виджеты обновятся, пока приложение запущено.

## Строка меню

Индикатор в строке меню показывает подробные лимиты или компактный процент. Нажмите на него, чтобы открыть окно с доступными лимитами, временем сброса, свежестью данных и настройками. Когда выходит новая версия, рядом со значением появляется стрелка, а во всплывающем окне — карточка обновления.

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

В настройках выбираются оформление окна и режим строки меню. Если доступны оба лимита, здесь же выбирается источник процента для компактного индикатора. В разделе `Updates` указаны установленная версия, результат последней проверки и действие для обновления.

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

## Обновления

Проверка последнего публичного релиза на GitHub выполняется при запуске приложения, а затем каждые четыре часа. Запустить её вручную можно в настройках.

Если доступна новая версия, уведомление появится в строке меню, во всплывающем окне и в настройках. После нажатия `Update now` загрузится официальный ZIP для macOS. Перед установкой проверяются контрольная сумма SHA-256 из ответа GitHub, идентификатор пакета, версия и подпись кода. После проверки текущая копия в `Applications` заменяется, затем автоматически открывается новая версия.

Если изменить папку `Applications` не получается, откройте `Open release page` и установите DMG вручную.

## Приватность

Данные об использовании и лимитах Codex остаются на Mac. Для виджетов хранится небольшой локальный снимок из сессии Codex CLI. При проверке обновлений в публичный API GitHub передаётся только номер установленной версии, без данных об использовании Codex. Собственного сервера у проекта нет.

## Удаление

Завершите Codex Limit Widget и удалите приложение из папки `Applications`.

Если после удаления виджет всё ещё виден в галерее, перезагрузите Mac и удалите другие локальные копии `Codex Limit Widget.app`.
