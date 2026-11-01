# Atualização 0.2 — Relatórios e Patrimônio

## Relatórios
- Área de conteúdo centralizada com largura máxima de 1180 px.
- Comparação de entradas e despesas com o período anterior.
- Gráfico de colunas com uma única escala e meses vazios sem barras artificiais.
- Categorias ordenadas por gasto, com percentual e acesso aos lançamentos por clique.
- Resumo do período e cards de trabalho por cliente.
- Exportação CSV mantida.

## Patrimônio
Acesse Configurações → Patrimônio. Os valores começam ocultos; toque no olho para mostrar.
Cadastre contas bancárias, investimentos, dinheiro guardado e outras reservas.
Informe o saldo atual completo, em reais, e a data da atualização. Ao editar, o valor anterior é substituído no total, mantendo o histórico.
O total soma somente a última versão de cada reserva ativa. O resultado mensal e as dívidas de clientes não são somados.
Não duplique o saldo de um investimento dentro do saldo da conta bancária. Não há integração automática com instituições financeiras ou cálculo de rendimentos.
Saldos sem atualização há mais de 30 dias são sinalizados.
Ocultar é uma medida visual, não senha, criptografia ou bloqueio de acesso ao banco.

## Dados e sincronização
O banco existente não é apagado ou substituído pela atualização. O novo tipo de registro usa o mesmo histórico de operações, backup e sincronização.
Atualize PC e Android para esta versão antes de sincronizar reservas: a versão 0.1 não reconhece o novo tipo e recusará a importação, preservando seus dados locais.
Não volte para a versão 0.1 depois de cadastrar patrimônio sem antes preservar um backup da versão atual.

## Aplicar / executar
A atualização do código-fonte exige recompilar ou executar novamente o aplicativo. Abrir um executável antigo não mostra as novas telas.

Na pasta do projeto:
    flutter pub get
    flutter test
    flutter run -d windows

Para uma distribuição Windows:
    flutter build windows --release

Para atualizar o APK de teste:
    flutter build apk --debug

Preserve a mesma assinatura e o identificador do Android. Faça um backup pelo próprio aplicativo antes de instalar uma nova versão.

## Validação desta atualização — 30/10/2026
- Formatação dos arquivos Dart concluída.
- 38 casos verificados: 34 casos de regras, persistência, sincronização e navegação passaram na execução da suíte; os 4 testes da nova interface foram reexecutados e aprovados após corrigir o posicionamento do clique no teste de celular.
- Testes de relatório em 390×844 e 1440×1100, com inspeção de uma prévia renderizada pelo Flutter usando dados fictícios.
- O analisador independente encerrou por uma falha de processo neste ambiente; não foi registrado como aprovado.
- A sincronização com a conta Google real e o APK Android não foram revalidados nesta atualização. Os testes de sincronização usam transporte HTTP controlado.
- A tentativa de gerar o executável Windows release falhou no processo nativo com "Invalid handle" / MSB8066. Nenhum executável novo foi entregue. O código foi aplicado; execute os comandos acima no seu terminal para recompilar.
