(function () {
  var detailCache = {};
  var detailRequestSerial = 0;

  function runInsertedScripts(container) {
    Array.prototype.forEach.call(container.querySelectorAll('script'), function (script) {
      var replacement = document.createElement('script');
      Array.prototype.forEach.call(script.attributes, function (attr) {
        replacement.setAttribute(attr.name, attr.value);
      });
      replacement.text = script.text || script.textContent || script.innerHTML || '';
      script.parentNode.replaceChild(replacement, script);
    });
  }

  function setDetailContent(content, html) {
    content.innerHTML = html;
    runInsertedScripts(content);
  }

  function showPanel(button) {
    var detail = document.getElementById('txhm-detail');
    var content = document.getElementById('txhm-detail-content');
    var url = button.getAttribute('data-detail-url');
    if (!detail || !content || !url) return;

    var placeholder = detail.querySelector('.txhm-detail-placeholder');
    if (placeholder) placeholder.hidden = true;
    content.hidden = false;

    detail.scrollIntoView({ block: 'nearest', behavior: 'smooth' });

    if (detailCache[url]) {
      setDetailContent(content, detailCache[url]);
      return;
    }

    var requestSerial = ++detailRequestSerial;
    content.innerHTML = '<p class="nodata">불러오는 중...</p>';

    fetch(url, {
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'XMLHttpRequest' }
    }).then(function (response) {
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.text();
    }).then(function (html) {
      if (requestSerial !== detailRequestSerial) return;
      detailCache[url] = html;
      setDetailContent(content, html);
    }).catch(function () {
      if (requestSerial !== detailRequestSerial) return;
      content.innerHTML = '<p class="nodata">셀 상세를 불러오지 못했습니다.</p>';
    });
  }

  function updatePeriodControls(select) {
    var form = select.closest && select.closest('form.txhm-toolbar');
    if (!form) return;

    var unit = select.value === 'month' ? 'month' : 'week';
    var label = unit === 'month' ? '월' : '주';

    Array.prototype.forEach.call(form.querySelectorAll('[data-txhm-period-label]'), function (item) {
      item.textContent = label;
    });

    Array.prototype.forEach.call(form.querySelectorAll('[data-txhm-period-input]'), function (input) {
      var bound = input.getAttribute('data-txhm-period-input');
      var value = form.getAttribute('data-txhm-' + unit + '-' + bound);

      input.setAttribute('type', unit);
      if (value) input.value = value;
    });
  }

  function roomKeyMatches(element, roomKey) {
    return element && element.getAttribute('data-txhm-room-key') === roomKey;
  }

  function updateRoomRowspan(tbody, roomKey) {
    if (!tbody || !roomKey) return;

    var roomCell = null;
    Array.prototype.some.call(tbody.querySelectorAll('[data-txhm-room-cell]'), function (cell) {
      if (!roomKeyMatches(cell, roomKey)) return false;
      roomCell = cell;
      return true;
    });
    if (!roomCell) return;

    var visibleRows = 0;
    Array.prototype.forEach.call(tbody.querySelectorAll('tr[data-txhm-room-key]'), function (row) {
      if (!roomKeyMatches(row, roomKey) || row.hidden) return;
      visibleRows += 1;
    });
    if (visibleRows > 0) roomCell.rowSpan = visibleRows;
  }

  function toggleMemberRows(button) {
    var rowIndex = button.getAttribute('data-row-index');
    var groupRow = button.closest && button.closest('tr');
    var tbody = groupRow && groupRow.parentNode;
    if (!tbody || !rowIndex) return;

    var expanded = button.getAttribute('aria-expanded') === 'true';
    var nextExpanded = !expanded;
    var roomKey = groupRow.getAttribute('data-txhm-room-key');

    Array.prototype.forEach.call(tbody.querySelectorAll('[data-txhm-member-row]'), function (row) {
      if (row.getAttribute('data-txhm-parent-row') !== rowIndex) return;
      row.hidden = !nextExpanded;
    });

    button.setAttribute('aria-expanded', nextExpanded ? 'true' : 'false');
    var mark = button.querySelector('.txhm-toggle-mark');
    if (mark) mark.textContent = nextExpanded ? '-' : '+';
    updateRoomRowspan(tbody, roomKey);
  }

  document.addEventListener('click', function (event) {
    var toggleButton = event.target.closest && event.target.closest('[data-txhm-toggle-members]');
    if (toggleButton) {
      toggleMemberRows(toggleButton);
      return;
    }

    var button = event.target.closest && event.target.closest('.txhm-cell');
    if (!button) return;
    showPanel(button);
  });

  document.addEventListener('change', function (event) {
    var select = event.target;
    if (!select || select.name !== 'period_unit') return;
    updatePeriodControls(select);
  });
})();
