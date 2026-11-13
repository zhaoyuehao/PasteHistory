export const markup = `<main id="desk" tabindex="-1" aria-label="海的桌面模拟器">
      <div id="coast"></div>
      <canvas id="water" aria-hidden="true"></canvas
      ><canvas id="rain" aria-hidden="true"></canvas>
      <header>
        <button id="product" aria-haspopup="menu"><strong>海的桌面</strong></button
        ><button id="files" aria-haspopup="true">文件</button
        ><button id="view" aria-haspopup="true">显示</button>
        <button id="clipboard" title="打开许愿树剪贴板">PasteHistory</button><div class="space"></div>
        <select id="sea-language" aria-label="语言"></select><button id="skies" aria-haspopup="true" title="天气与昼夜">
          ☼ <span id="condition">天气</span></button
        ><time id="clock"></time>
      </header>
      <div id="fleet" aria-label="桌面文件"></div>
      <div id="popup" class="panel" hidden></div>
      <dialog id="sheet">
        <div class="titlebar">
          <button id="close" aria-label="关闭窗口">×</button
          ><b id="heading"></b>
        </div>
        <div id="contents"></div>
      </dialog>
      <input type="file" id="input" multiple hidden /><span
        id="status"
        role="status"
        aria-live="polite"
      ></span>
    </main>`;
