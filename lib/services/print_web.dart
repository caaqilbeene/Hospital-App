import 'dart:js' as js;
import 'dart:convert' show jsonEncode;

void printPrescription({
  required String doctorName,
  required String specialty,
  required String patientName,
  required String date,
  required String age,
  required String gender,
  required String diagnosis,
  required String prescription,
  required String patientId,
  required String weight,
}) {
  final htmlContent = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Medical Prescription - $patientName</title>
  <style>
    @media print {
      body {
        margin: 0;
        padding: 0;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }
      .prescription-container {
        border: none !important;
        box-shadow: none !important;
      }
    }
    
    body {
      font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      margin: 0;
      padding: 20px;
      background-color: #f1f5f9;
      display: flex;
      justify-content: center;
    }

    .prescription-container {
      width: 790px;
      height: 1080px;
      background: white;
      border: 1px solid #cbd5e1;
      box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.05);
      box-sizing: border-box;
      display: flex;
      flex-direction: column;
      position: relative;
    }

    .header-banner {
      background: linear-gradient(135deg, #0284c7, #0369a1);
      padding: 30px 40px;
      display: flex;
      align-items: center;
      position: relative;
    }

    .header-banner::after {
      content: '';
      position: absolute;
      bottom: 0;
      left: 0;
      width: 100%;
      height: 24px;
      background-color: white;
      clip-path: ellipse(65% 100% at 50% 100%);
    }

    .logo-container {
      width: 64px;
      height: 64px;
      background: white;
      border-radius: 14px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
      margin-right: 20px;
      z-index: 10;
    }

    .logo-container svg {
      width: 38px;
      height: 38px;
      fill: #0284c7;
    }

    .hospital-info {
      z-index: 10;
      color: white;
    }

    .hospital-title {
      font-size: 32px;
      font-weight: 800;
      letter-spacing: 0.5px;
      margin: 0;
    }

    .hospital-subtitle {
      font-size: 14px;
      opacity: 0.9;
      margin: 4px 0 0 0;
      text-transform: uppercase;
      letter-spacing: 1px;
    }

    .doctor-info-bar {
      padding: 20px 40px 12px 40px;
      border-bottom: 2px solid #e2e8f0;
      background-color: #fafafa;
    }

    .doctor-name {
      color: #0284c7;
      font-size: 20px;
      font-weight: 700;
      margin: 0;
    }

    .doctor-spec {
      color: #64748b;
      font-size: 13px;
      font-weight: 600;
      margin: 4px 0 0 0;
      text-transform: uppercase;
      letter-spacing: 1px;
    }

    .patient-info-table {
      padding: 20px 40px;
      background-color: #f8fafc;
      border-bottom: 2px solid #e2e8f0;
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 12px 30px;
      font-size: 14px;
    }

    .info-row {
      display: flex;
      align-items: flex-end;
      border-bottom: 1px dotted #cbd5e1;
      padding-bottom: 4px;
    }

    .info-label {
      font-weight: 700;
      color: #64748b;
      width: 105px;
      flex-shrink: 0;
    }

    .info-val {
      color: #1e293b;
      font-weight: 600;
    }

    .prescription-body {
      flex: 1;
      padding: 40px;
      position: relative;
      display: flex;
      flex-direction: column;
    }

    .stethoscope-watermark {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      width: 320px;
      height: 320px;
      opacity: 0.04;
      pointer-events: none;
      z-index: 1;
    }

    .rx-title {
      font-size: 46px;
      font-family: 'Georgia', Times, serif;
      font-weight: 700;
      font-style: italic;
      color: #0f172a;
      margin-bottom: 20px;
      z-index: 2;
    }

    .prescription-content {
      font-size: 16px;
      line-height: 1.8;
      color: #334155;
      white-space: pre-wrap;
      z-index: 2;
      flex: 1;
    }

    .signature-container {
      align-self: flex-end;
      width: 240px;
      text-align: center;
      margin-top: 30px;
      z-index: 5;
    }

    .sig-line {
      border-bottom: 1.5px solid #64748b;
      height: 45px;
      margin-bottom: 8px;
    }

    .sig-title {
      font-size: 13px;
      color: #64748b;
      font-weight: 600;
    }

    .footer-bar {
      background-color: #0284c7;
      color: white;
      padding: 18px 40px;
      display: flex;
      justify-content: space-between;
      font-size: 12px;
      font-weight: 500;
    }

    .footer-col {
      display: flex;
      align-items: center;
    }
  </style>
</head>
<body>
  <div class="prescription-container">
    <div class="header-banner">
      <div class="logo-container">
        <!-- Shield Medical Cross Logo -->
        <svg viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-4H7v-2h4V7h2v4h4v2h-4v4z"/>
        </svg>
      </div>
      <div class="hospital-info">
        <h1 class="hospital-title">Nasiib Hospital</h1>
        <p class="hospital-subtitle">Quality & Caring Healthcare</p>
      </div>
    </div>
    
    <div class="doctor-info-bar">
      <h2 class="doctor-name">Dr. $doctorName</h2>
      <p class="doctor-spec">$specialty</p>
    </div>
    
    <div class="patient-info-table">
      <div class="info-row">
        <span class="info-label">Patient Name:</span>
        <span class="info-val">$patientName</span>
      </div>
      <div class="info-row">
        <span class="info-label">Date:</span>
        <span class="info-val">$date</span>
      </div>
      <div class="info-row">
        <span class="info-label">Age:</span>
        <span class="info-val">$age</span>
      </div>
      <div class="info-row">
        <span class="info-label">Gender:</span>
        <span class="info-val">$gender</span>
      </div>
      <div class="info-row">
        <span class="info-label">Weight:</span>
        <span class="info-val">$weight</span>
      </div>

      <div class="info-row" style="grid-column: span 2; border-bottom: none;">
        <span class="info-label">Diagnosis:</span>
        <span class="info-val" style="color: #0284c7; font-weight: 700;">$diagnosis</span>
      </div>
    </div>
    
    <div class="prescription-body">
      <!-- Watermark Stethoscope Icon SVG -->
      <svg class="stethoscope-watermark" viewBox="0 0 24 24" fill="#0284c7">
        <path d="M12 3c-4.97 0-9 4.03-9 9 0 2.12.74 4.07 1.97 5.61L4.35 19.4c-.39.39-.39 1.02 0 1.41.39.39 1.02.39 1.41 0l1.9-1.9C9.07 19.57 10.48 20 12 20c4.97 0 9-4.03 9-9V3h-9zm7 8c0 3.86-3.14 7-7 7s-7-3.14-7-7 3.14-7 7-7h5v7z"/>
      </svg>
      
      <div class="prescription-content">$prescription</div>
      
      <div class="signature-container">
        <div class="sig-line"></div>
        <div class="sig-title">Authorized Doctor Signature</div>
      </div>
    </div>
    
    <div class="footer-bar">
      <div class="footer-col">📍 24 Nasiib Street, Mogadishu</div>
      <div class="footer-col">📞 +252 61 123 4567</div>
      <div class="footer-col">✉️ contact@nasiibhospital.so</div>
    </div>
  </div>
  
  <script>
    window.onload = function() {
      setTimeout(function() {
        window.print();
      }, 300);
    }
  </script>
</body>
</html>
  """;

  js.context.callMethod('eval', ["""
    var printWindow = window.open('', '_blank');
    printWindow.document.write(${jsonEncode(htmlContent)});
    printWindow.document.close();
  """]);
}
