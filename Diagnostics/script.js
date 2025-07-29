// Configurações
const CGI_URL = '/cgi-bin/system-diagnostic.cgi';
const WEB_PORT = '1298';

// Variáveis globais de controle
let diagnosticRunning = false;
let currentRequestId = null;
let currentTest = null;
let diagnosticResults = {};

// === FUNÇÃO PRINCIPAL: DIAGNÓSTICO COMPLETO ===
async function runFullDiagnostic() {
    if (diagnosticRunning) {
        showAlert('⏳ Diagnóstico em andamento! Aguarde...', 'warning');
        return;
    }
    
    diagnosticRunning = true;
    currentRequestId = Date.now();
    
    // Desabilitar botão visualmente
    const button = document.querySelector('[onclick="runFullDiagnostic()"]');
    if (button) {
        button.disabled = true;
        button.style.opacity = '0.5';
        button.innerHTML = '⏳ Executando...';
        button.style.cursor = 'not-allowed';
    }
        
    showLoading('Executando diagnóstico completo do sistema... por favor, não feche ou saia desta página!');
    
    // Progresso OTIMIZADO
    const progressSteps = [
        { percent: 0, message: 'Iniciando diagnóstico do sistema...', delay: 500 },
        { percent: 5, message: 'Verificando consistência do armazenamento...', delay: 2000 },
        { percent: 15, message: 'Analisando integridade dos sistemas de arquivos...', delay: 2500 },
        { percent: 25, message: 'Verificando dispositivos SMART...', delay: 2000 },
        { percent: 35, message: 'Testando servidores DNS...', delay: 3000 },
        { percent: 50, message: 'Verificando interfaces de rede...', delay: 1500 },
        { percent: 60, message: 'Analisando serviços críticos do sistema...', delay: 2000 },
        { percent: 70, message: 'Verificando Docker e containers...', delay: 1500 },
        { percent: 80, message: 'Analisando carga, memória e processos...', delay: 1000 },
        { percent: 85, message: 'Coletando logs de erro do sistema...', delay: 500 }
    ];

    let currentStep = 0;
    let progressCompleted = false;
    showProgress(progressSteps[0].percent, progressSteps[0].message);

    function advanceProgress() {
        if (progressCompleted || currentStep >= progressSteps.length) return;
        
        currentStep++;
        if (currentStep < progressSteps.length) {
            const step = progressSteps[currentStep];
            showProgress(step.percent, step.message);
            setTimeout(advanceProgress, step.delay);
        }
    }

    setTimeout(advanceProgress, progressSteps[0].delay);

    try {
        const startTime = Date.now();
        
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'full-diagnostic' })
        });

        progressCompleted = true;
        const duration = Math.round((Date.now() - startTime) / 1000);
        
        showProgress(90, 'Processando resultados...');
        await sleep(300);
        showProgress(95, 'Analisando dados coletados...');
        await sleep(200);
        showProgress(100, `Diagnóstico concluído em ${duration}s!`);

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        
        setTimeout(() => {
            processResults(data, 'Diagnóstico Completo');
        }, 600);

    } catch (error) {
        progressCompleted = true;
        hideLoading();
        hideProgress();
        showAlert('Erro ao executar diagnóstico: ' + error.message, 'error');
    } finally {
        // SEMPRE libera a trava
        diagnosticRunning = false;
        currentRequestId = null;
        if (button) {
            button.disabled = false;
            button.style.opacity = '1';
            button.innerHTML = '🚀 Diagnóstico Completo';
            button.style.cursor = 'pointer';
        }
    }
}

// === FUNÇÃO: TESTES ESPECÍFICOS COM PROTEÇÃO ===
async function runSpecificTest(testType) {
    if (diagnosticRunning) {
        showAlert('⏳ Diagnóstico em andamento! Aguarde...', 'warning');
        return;
    }
    
    diagnosticRunning = true;
    
    const testConfigs = {
        'storage': {
            name: 'Teste de Armazenamento',
            steps: [
                { percent: 0, message: 'Iniciando teste de armazenamento...', delay: 500 },
                { percent: 20, message: 'Verificando montagens do fstab...', delay: 1500 },
                { percent: 40, message: 'Analisando dispositivos SMART...', delay: 2000 },
                { percent: 60, message: 'Verificando uso de disco...', delay: 1500 },
                { percent: 80, message: 'Verificando inodes...', delay: 1000 }
            ]
        },
        'network': {
            name: 'Teste de Rede',
            steps: [
                { percent: 0, message: 'Iniciando teste de rede...', delay: 500 },
                { percent: 30, message: 'Testando 8 servidores DNS...', delay: 3000 },
                { percent: 70, message: 'Verificando interfaces...', delay: 1500 },
                { percent: 85, message: 'Verificando resolução DNS...', delay: 1000 }
            ]
        },
        'services': {
            name: 'Teste de Serviços',
            steps: [
                { percent: 0, message: 'Iniciando teste de serviços...', delay: 500 },
                { percent: 25, message: 'Verificando serviços críticos...', delay: 1500 },
                { percent: 50, message: 'Analisando Docker...', delay: 2000 },
                { percent: 75, message: 'Verificando LibVirt...', delay: 1000 }
            ]
        },
        'system': {
            name: 'Teste de Sistema',
            steps: [
                { percent: 0, message: 'Iniciando análise do sistema...', delay: 500 },
                { percent: 30, message: 'Verificando carga e memória...', delay: 1000 },
                { percent: 60, message: 'Analisando processos zumbi...', delay: 1000 },
                { percent: 85, message: 'Coletando logs de erro...', delay: 1500 }
            ]
        }
    };

    const config = testConfigs[testType] || {
        name: 'Teste Específico',
        steps: [
            { percent: 0, message: 'Iniciando teste...', delay: 500 },
            { percent: 50, message: 'Executando...', delay: 2000 },
            { percent: 80, message: 'Finalizando...', delay: 1000 }
        ]
    };

    showLoading(`Executando ${config.name.toLowerCase()}...`);
    
    let currentStep = 0;
    let isCompleted = false;
    showProgress(config.steps[0].percent, config.steps[0].message);

    function advanceStep() {
        if (isCompleted || currentStep >= config.steps.length) return;
        
        currentStep++;
        if (currentStep < config.steps.length) {
            const step = config.steps[currentStep];
            showProgress(step.percent, step.message);
            setTimeout(advanceStep, step.delay);
        }
    }

    setTimeout(advanceStep, config.steps[0].delay);

    try {
        const startTime = Date.now();
        
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                action: 'specific-test',
                test: testType
            })
        });

        isCompleted = true;
        const duration = Math.round((Date.now() - startTime) / 1000);
        
        showProgress(95, 'Processando resultados...');
        await sleep(200);
        showProgress(100, `${config.name} concluído em ${duration}s!`);

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        
        setTimeout(() => {
            processResults(data, config.name);
        }, 400);

    } catch (error) {
        isCompleted = true;
        hideLoading();
        hideProgress();
        showAlert('Erro ao executar teste: ' + error.message, 'error');
    } finally {
        // SEMPRE libera a trava
        diagnosticRunning = false;
    }
}

// === FUNÇÕES DE PROCESSAMENTO ===
function processResults(data, testName) {
    hideLoading();
    hideProgress();

    let results;
    try {
        results = JSON.parse(data);
    } catch (e) {
        results = { output: data };
    }

    const analysis = analyzeResults(results.output || data);
    showResults(results.output || data, testName, analysis);
    updateSummary(analysis);
}

function analyzeResults(output) {
    const analysis = { status: 'unknown', errors: 0, warnings: 0, tests: 0, sections: [] };
    if (!output) return analysis;

    // Extrair do resumo final (mais confiável)
    const errorMatch = output.match(/Erros críticos encontrados: (\d+)/);
    const warningMatch = output.match(/Avisos encontrados: (\d+)/);
    
    if (errorMatch) analysis.errors = parseInt(errorMatch[1]);
    if (warningMatch) analysis.warnings = parseInt(warningMatch[1]);

    const testMatches = output.match(/🔍 Teste \d+:/g);
    analysis.tests = testMatches ? testMatches.length : 0;

    if (analysis.errors > 0) analysis.status = 'error';
    else if (analysis.warnings > 0) analysis.status = 'warning';  
    else analysis.status = 'success';

    return analysis;
}

// === FUNÇÕES DE UI ===
function showResults(output, testName, analysis) {
    const container = document.getElementById('result-container');
    const title = document.getElementById('result-title');
    const content = document.getElementById('result-content');

    title.textContent = `${testName} - ${new Date().toLocaleString('pt-BR')}`;
    content.innerHTML = `<pre>${output}</pre>`;
    container.className = `result-container active ${analysis.status}`;

    if (analysis.status === 'success') {
        showAlert('Diagnóstico concluído com sucesso! Sistema saudável.', 'success');
    } else if (analysis.status === 'warning') {
        showAlert(`Diagnóstico concluído com ${analysis.warnings} aviso(s). Verificar itens mencionados.`, 'warning');
    } else {
        showAlert(`Diagnóstico concluído com ${analysis.errors} erro(s) crítico(s). Ação imediata necessária!`, 'error');
    }
}

function updateSummary(analysis) {
    const summaryContainer = document.getElementById('result-summary');
    const statusElement = document.getElementById('summary-status');
    const errorsElement = document.getElementById('summary-errors');
    const warningsElement = document.getElementById('summary-warnings');
    const testsElement = document.getElementById('summary-tests');

    summaryContainer.style.display = 'block';

    statusElement.textContent = getStatusText(analysis.status);
    statusElement.className = `summary-value ${analysis.status}`;
    errorsElement.textContent = analysis.errors;
    errorsElement.className = `summary-value ${analysis.errors > 0 ? 'error' : 'success'}`;
    warningsElement.textContent = analysis.warnings;
    warningsElement.className = `summary-value ${analysis.warnings > 0 ? 'warning' : 'success'}`;
    testsElement.textContent = analysis.tests || 'Completo';
    testsElement.className = 'summary-value success';
}

function getStatusText(status) {
    switch (status) {
        case 'success': return '✅ Saudável';
        case 'warning': return '⚠️ Com Avisos';
        case 'error': return '❌ Crítico';
        default: return '❓ Desconhecido';
    }
}

// === INFORMAÇÕES DO SISTEMA ===
async function showSystemInfo() {
    const infoContainer = document.getElementById('system-info');
    const detailsElement = document.getElementById('system-details');

    const isVisible = window.getComputedStyle(infoContainer).display === 'block';
    if (isVisible) {
        infoContainer.style.display = 'none';
        return;
    }

    infoContainer.style.display = 'block';
    
    const currentContent = detailsElement.innerHTML;
    const hasValidContent = currentContent.includes('<pre style=') || 
                          currentContent.includes('Sistema Operacional') ||
                          (currentContent.length > 100 && !currentContent.includes('🔄 Carregando'));
    
    if (hasValidContent) return;

    detailsElement.innerHTML = '<p>🔄 Carregando informações do sistema...</p>';

    try {
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'system-info' })
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        detailsElement.innerHTML = `<pre style="background: white; padding: 15px; border-radius: 8px; color: #2c3e50; font-family: monospace;">${data}</pre>`;

    } catch (error) {
        console.log('Erro ao carregar do CGI:', error.message);
        
        const fallbackInfo = `📊 Informações do Sistema (Navegador)
=====================================
🖥️ Sistema Operacional: ${navigator.platform}
🌐 Navegador: ${navigator.userAgent.split(' ')[0]}
📱 Resolução: ${screen.width}x${screen.height}
🕐 Data/Hora: ${new Date().toLocaleString('pt-BR')}
🌍 Idioma: ${navigator.language}
⚡ Cookies: ${navigator.cookieEnabled ? 'Sim' : 'Não'}
🔌 Online: ${navigator.onLine ? 'Sim' : 'Não'}
💾 Memória: ${navigator.deviceMemory ? navigator.deviceMemory + ' GB' : 'N/A'}
🔄 CPU Cores: ${navigator.hardwareConcurrency || 'N/A'}

⚠️ Nota: Servidor CGI não disponível.`;

        detailsElement.innerHTML = `<pre style="background: white; padding: 15px; border-radius: 8px; color: #2c3e50; font-family: monospace;">${fallbackInfo}</pre>`;
    }
}

async function loadSystemInfo() {
    try {
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'quick-info' })
        });
        // Processar se necessário
    } catch (error) {
        console.log('Informações do sistema não disponíveis');
    }
}

// === FUNÇÕES DE CONTROLE ===
function showLoading(text = 'Processando...') {
    const loading = document.getElementById('loading');
    const loadingText = document.getElementById('loading-text');
    loadingText.textContent = text;
    loading.classList.add('active');
}

function hideLoading() {
    document.getElementById('loading').classList.remove('active');
}

function showProgress(percent, text = '') {
    const container = document.getElementById('progress-container');
    const fill = document.getElementById('progress-fill');
    const textElement = document.getElementById('progress-text');

    if (container) container.style.display = 'block';
    if (fill) fill.style.width = `${percent}%`;
    if (textElement && text) textElement.textContent = text;
}

function hideProgress() {
    const container = document.getElementById('progress-container');
    if (container) container.style.display = 'none';
}

function showAlert(message, type = 'success') {
    const alert = document.getElementById('alert-container');
    alert.textContent = message;
    alert.className = `alert alert-${type} active`;
    setTimeout(() => alert.classList.remove('active'), 5000);
}

// === FUNÇÕES DE AÇÃO ===
function downloadResults() {
    const content = document.getElementById('result-content');
    if (!content.textContent.trim()) {
        showAlert('Nenhum resultado para baixar', 'warning');
        return;
    }

    // Criar modal simples de escolha
    const modal = document.createElement('div');
    modal.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0,0,0,0.8);
        z-index: 10000;
        display: flex;
        justify-content: center;
        align-items: center;
    `;

    const modalContent = document.createElement('div');
    modalContent.style.cssText = `
        background: white;
        border-radius: 12px;
        padding: 30px;
        max-width: 400px;
        width: 90%;
        text-align: center;
        box-shadow: 0 20px 40px rgba(0,0,0,0.3);
    `;

    modalContent.innerHTML = `
        <h3 style="margin-bottom: 25px; color: #2c3e50;">Baixar Relatorio</h3>
        
        <button onclick="downloadTXT()" style="
            width: 100%; 
            margin: 10px 0; 
            padding: 15px; 
            background: #3498db; 
            color: white; 
            border: none; 
            border-radius: 8px; 
            cursor: pointer; 
            font-size: 16px;
            transition: background 0.3s ease;
        " onmouseover="this.style.background='#2980b9'" onmouseout="this.style.background='#3498db'">
            Arquivo de Texto (TXT)
        </button>
        
        <button onclick="downloadPDF()" style="
            width: 100%; 
            margin: 10px 0; 
            padding: 15px; 
            background: #e74c3c; 
            color: white; 
            border: none; 
            border-radius: 8px; 
            cursor: pointer; 
            font-size: 16px;
            transition: background 0.3s ease;
        " onmouseover="this.style.background='#c0392b'" onmouseout="this.style.background='#e74c3c'">
            Relatorio PDF
        </button>
        
        <button onclick="closeModal()" style="
            width: 100%; 
            margin: 10px 0; 
            padding: 12px; 
            background: #95a5a6; 
            color: white; 
            border: none; 
            border-radius: 8px; 
            cursor: pointer;
            transition: background 0.3s ease;
        " onmouseover="this.style.background='#7f8c8d'" onmouseout="this.style.background='#95a5a6'">
            Cancelar
        </button>
    `;

    modal.appendChild(modalContent);
    modal.id = 'download-modal';
    document.body.appendChild(modal);

    // Funções do modal
    window.downloadTXT = () => {
        const blob = new Blob([content.textContent], { type: 'text/plain' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `diagnostico-sistema-${new Date().toISOString().slice(0, 19).replace(/:/g, '-')}.txt`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
        showAlert('Arquivo TXT baixado com sucesso!', 'success');
        closeModal();
    };

    window.downloadPDF = () => {
        closeModal();
        generateMinimalPDF();
    };

    window.closeModal = () => {
        const modal = document.getElementById('download-modal');
        if (modal) document.body.removeChild(modal);
    };

    // Fechar clicando fora
    modal.onclick = (e) => {
        if (e.target === modal) closeModal();
    };
}

// Função para limpar texto de emojis e caracteres especiais
function cleanText(text) {
    return text
        // Remover emojis
        .replace(/[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F700}-\u{1F77F}]|[\u{1F780}-\u{1F7FF}]|[\u{1F800}-\u{1F8FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]/gu, '')
        // Substituir caracteres acentuados
        .replace(/[áàâãä]/g, 'a')
        .replace(/[ÁÀÂÃÄ]/g, 'A')
        .replace(/[éèêë]/g, 'e')
        .replace(/[ÉÈÊË]/g, 'E')
        .replace(/[íìîï]/g, 'i')
        .replace(/[ÍÌÎÏ]/g, 'I')
        .replace(/[óòôõö]/g, 'o')
        .replace(/[ÓÒÔÕÖ]/g, 'O')
        .replace(/[úùûü]/g, 'u')
        .replace(/[ÚÙÛÜ]/g, 'U')
        .replace(/[ç]/g, 'c')
        .replace(/[Ç]/g, 'C')
        .replace(/[ñ]/g, 'n')
        .replace(/[Ñ]/g, 'N')
        // Substituir símbolos por equivalentes ASCII
        .replace(/✅/g, '[OK]')
        .replace(/❌/g, '[ERRO]')
        .replace(/⚠️/g, '[AVISO]')
        .replace(/🔍/g, '')
        .replace(/📋/g, '')
        .replace(/📅/g, '')
        .replace(/🌐/g, '')
        .replace(/💾/g, '')
        .replace(/🔧/g, '')
        .replace(/🚨/g, '[CRITICO]')
        .replace(/ℹ️/g, '[INFO]')
        // Limpar espaços extras
        .replace(/\s+/g, ' ')
        .trim();
}

async function generateMinimalPDF() {
    try {
        showAlert('Gerando PDF...', 'info');
        
        // Carregar jsPDF se necessário
        if (typeof window.jsPDF === 'undefined') {
            await loadJsPDF();
        }

        const content = document.getElementById('result-content').textContent;
        const title = document.getElementById('result-title').textContent;
        const timestamp = new Date().toLocaleString('pt-BR');

        // Criar PDF
        const doc = new jsPDF({
            orientation: 'portrait',
            unit: 'mm',
            format: 'a4'
        });

        // Configurações
        const pageWidth = doc.internal.pageSize.getWidth();
        const pageHeight = doc.internal.pageSize.getHeight();
        const margin = 20;
        const lineHeight = 4;
        const maxWidth = pageWidth - (margin * 2);
        
        let currentY = margin;

        // Função para verificar quebra de página
        const checkPageBreak = (neededSpace = 10) => {
            if (currentY + neededSpace > pageHeight - margin) {
                doc.addPage();
                currentY = margin;
                return true;
            }
            return false;
        };

        // Função para adicionar texto
        const addText = (text, fontSize = 10, isBold = false) => {
            doc.setFontSize(fontSize);
            doc.setFont(undefined, isBold ? 'bold' : 'normal');
            
            const lines = doc.splitTextToSize(text, maxWidth);
            lines.forEach(line => {
                checkPageBreak();
                doc.text(line, margin, currentY);
                currentY += lineHeight;
            });
        };

        // === CABEÇALHO ===
        doc.setTextColor(41, 128, 185);
        addText('RELATORIO DE DIAGNOSTICO DO SISTEMA', 16, true);
        currentY += 5;
        
        // Linha separadora
        doc.setDrawColor(200, 200, 200);
        doc.line(margin, currentY, pageWidth - margin, currentY);
        currentY += 10;

        // === INFORMAÇÕES BÁSICAS ===
        doc.setTextColor(0, 0, 0);
        addText(cleanText(title), 12, true);
        addText(`Data/Hora: ${timestamp}`, 10);
        addText(`Servidor: ${window.location.hostname}`, 10);
        currentY += 5;

        // === CONTEÚDO PRINCIPAL ===
        doc.setTextColor(52, 73, 94);
        addText('RESULTADO DO DIAGNOSTICO:', 12, true);
        currentY += 5;

        // Processar conteúdo removendo emojis e caracteres especiais
        doc.setTextColor(0, 0, 0);
        const lines = content.split('\n');
        
        lines.forEach(line => {
            if (line.trim()) {
                // Limpar linha de emojis e caracteres especiais
                const cleanedLine = cleanText(line);
                
                // Ajustar fonte baseado no tipo de linha
                if (cleanedLine.includes('===') || cleanedLine.includes('Teste')) {
                    currentY += 3;
                    addText(cleanedLine, 11, true);
                    currentY += 2;
                } else if (cleanedLine.includes('OK:') || cleanedLine.includes('ERRO:') || 
                          cleanedLine.includes('AVISO:') || cleanedLine.includes('CRITICO:')) {
                    addText(cleanedLine, 10);
                } else {
                    addText(cleanedLine, 9);
                }
            } else {
                currentY += 2; // Espaço para linhas vazias
            }
        });

        // === RODAPÉ ===
        const totalPages = doc.internal.getNumberOfPages();
        for (let i = 1; i <= totalPages; i++) {
            doc.setPage(i);
            doc.setFontSize(8);
            doc.setTextColor(128, 128, 128);
            doc.text(`Pagina ${i} de ${totalPages}`, pageWidth - margin - 20, pageHeight - 8);
            doc.text(`Sistema de Diagnostico WebUI`, margin, pageHeight - 8);
        }

        // Salvar
        const filename = `diagnostico-sistema-${new Date().toISOString().slice(0, 19).replace(/:/g, '-')}.pdf`;
        doc.save(filename);
        
        showAlert('PDF gerado com sucesso!', 'success');

    } catch (error) {
        console.error('Erro ao gerar PDF:', error);
        showAlert('Erro ao gerar PDF: ' + error.message, 'error');
    }
}

// Carregar jsPDF
function loadJsPDF() {
    return new Promise((resolve, reject) => {
        if (window.jsPDF) {
            resolve();
            return;
        }

        const script = document.createElement('script');
        script.src = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';
        script.onload = () => {
            window.jsPDF = window.jspdf.jsPDF;
            resolve();
        };
        script.onerror = () => reject(new Error('Falha ao carregar jsPDF'));
        document.head.appendChild(script);
    });
}

// Fechar modal com ESC
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        const modal = document.getElementById('download-modal');
        if (modal) document.body.removeChild(modal);
    }
});

function printResults() {
    const content = document.getElementById('result-content');
    if (!content.textContent.trim()) {
        showAlert('Nenhum resultado para imprimir', 'warning');
        return;
    }

    const printWindow = window.open('', '_blank');
    printWindow.document.write(`
    <html>
    <head>
    <title>Diagnóstico do Sistema</title>
    <style>
    body { font-family: monospace; margin: 20px; }
    pre { white-space: pre-wrap; font-size: 12px; }
    .header { border-bottom: 2px solid #333; padding-bottom: 10px; margin-bottom: 20px; }
    </style>
    </head>
    <body>
    <div class="header">
    <h1>🔍 Diagnóstico do Sistema</h1>
    <p>Data: ${new Date().toLocaleString('pt-BR')}</p>
    </div>
    <pre>${content.textContent}</pre>
    </body>
    </html>
    `);
    printWindow.document.close();
    printWindow.print();
}

function clearResults() {
    const container = document.getElementById('result-container');
    const summary = document.getElementById('result-summary');
    const content = document.getElementById('result-content');

    container.classList.remove('active');
    summary.style.display = 'none';
    content.innerHTML = '';
    showAlert('Resultados limpos', 'success');
}

// === FUNÇÕES AUXILIARES ===
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function addVisualEffects() {
    const cards = document.querySelectorAll('.menu-card');
    cards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-5px) scale(1.02)';
        });
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0) scale(1)';
        });
    });
}

async function checkCGIStatus() {
    try {
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'ping' })
        });
        return response.ok;
    } catch (error) {
        console.error('CGI não disponível:', error);
        return false;
    }
}

// === EVENTOS E INICIALIZAÇÃO ===
window.addEventListener('beforeunload', function(e) {
    if (diagnosticRunning) {
        e.preventDefault();
        e.returnValue = '⚠️ Diagnóstico em andamento! Sair agora pode deixar processos órfãos no servidor. Tem certeza?';
        return e.returnValue;
    }
});

window.addEventListener('load', function() {
    // Reset de estado
    diagnosticRunning = false;
    currentRequestId = null;
    
    // Carregar info do sistema
    loadSystemInfo();
    
    // Adicionar efeitos visuais
    addVisualEffects();
    
    // Verificar status do CGI
    checkCGIStatus().then(status => {
        if (!status) {
            showAlert('⚠️ Aviso: Servidor CGI pode não estar disponível. Verifique a configuração.', 'warning');
        }
    });
    
    console.log('Sistema de Diagnóstico WebUI carregado com proteções ativas!');
});

// Atalhos de teclado
document.addEventListener('keydown', function(e) {
    if (e.ctrlKey && e.key === 'd') {
        e.preventDefault();
        runFullDiagnostic();
    }
    if (e.ctrlKey && e.key === 's') {
        e.preventDefault();
        downloadResults();
    }
    if (e.key === 'Escape') {
        clearResults();
    }
});
