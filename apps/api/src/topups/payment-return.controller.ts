import { Controller, Get, Header } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';

/**
 * Public, static post-payment page. No JWT, no session, no redirects and no
 * provider data: Kashier sends the payer's browser here after checkout, and the
 * webhook (not this page) is what credits the wallet. Served by the same tunnel
 * as `/webhooks/kashier` under the global `/api/v1` prefix.
 */
export const PAYMENT_RETURN_HTML = `<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>تم استلام الدفع / Payment received</title>
  <style>
    :root { color-scheme: dark; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px;
      background: #03131e; color: #f4f8f5; font-family: system-ui, -apple-system, "Segoe UI", Tahoma, sans-serif; }
    main { width: min(100%, 460px); padding: 32px 28px; text-align: center; border-radius: 20px;
      background: #0b2432; border: 1px solid #1e3b49; box-shadow: 0 18px 50px rgba(0, 0, 0, .3); }
    .mark { width: 56px; height: 56px; margin: 0 auto 18px; display: grid; place-items: center;
      border-radius: 50%; background: #22c58b; color: #03131e; font-size: 30px; font-weight: 800; }
    h1 { margin: 0 0 10px; font-size: 22px; line-height: 1.6; }
    p { margin: 0; color: #b9cbc6; font-size: 15px; line-height: 1.7; }
    p + p { margin-top: 8px; direction: ltr; text-align: center; }
    hr { border: 0; border-top: 1px solid #1e3b49; margin: 20px 0; }
  </style>
</head>
<body>
  <main>
    <div class="mark" aria-hidden="true">✓</div>
    <h1>ارجع للتطبيق، تأكيد الدفع بيتم تلقائياً</h1>
    <p>لا حاجة لأي إجراء إضافي — سيظهر الرصيد بعد تأكيد الدفع.</p>
    <hr />
    <p lang="en">Return to the app — payment confirmation is automatic.</p>
  </main>
</body>
</html>
`;

@ApiTags('Payments')
@Controller('payment-return')
export class PaymentReturnController {
  @Get()
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store, max-age=0')
  page(): string {
    return PAYMENT_RETURN_HTML;
  }
}
