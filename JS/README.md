# ExeWatch — JavaScript Browser Sample

A single HTML page that demonstrates ExeWatch logging, timing, and error capture directly in the browser. No build tools required — just open the file.

## Requirements

- Any modern browser (Chrome, Firefox, Edge, Safari)
- No build tools, no npm

## Step-by-step

**Step 1** — Open `index.html` in a text editor and replace `YOUR_API_KEY_HERE` with your browser API key (starts with `ew_web_`, from [exewatch.com](https://exewatch.com)):

```javascript
window.ewConfig = {
  apiKey: 'YOUR_API_KEY_HERE',
  customerId: 'SampleCustomer',
  appVersion: '1.0.0',
  debug: true
};
```

**Step 2** — Open `index.html` in your browser (double-click the file, or use a local server).

**Step 3** — Click the buttons to try each feature: Logging, Timing, Breadcrumbs + Error, User Identity, Tags, Metrics.

**Step 4** — Open the ExeWatch dashboard to see your events arrive in real time.

## How it works

The sample loads the ExeWatch JavaScript SDK from CDN. Set `window.ewConfig` before the SDK script — the global `ew` object is then available immediately:

```html
<script>
  window.ewConfig = {
    apiKey: 'ew_web_xxxx',
    customerId: 'SampleCustomer'
  };
</script>
<script src="https://exewatch.com/static/js/exewatch.v1.min.js"></script>
```

```javascript
// Logging
ew.debug('Page loaded');
ew.info('User signed in', 'auth');
ew.error('API call failed', 'api');

// Breadcrumbs
ew.addBreadcrumb('Clicked checkout button', 'ui');

// Timing
ew.startTiming('api_call');
// ... your operation ...
ew.endTiming('api_call');

// User identity
ew.setUser({ id: 'user-42', email: 'jane@example.com', name: 'Jane Doe' });

// Tags & Metrics
ew.setTag('environment', 'production');
ew.incrementCounter('page_views', 1, 'sample');
ew.recordGauge('cart_items', 5, 'sample');
```
