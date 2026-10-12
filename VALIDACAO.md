# Registro de validação

## Executado nesta entrega

- Leitura integral da especificação e uso da imagem original fornecida.
- Consulta à documentação oficial dos pacotes e dos fluxos OAuth/Drive.
- Download do SDK estável Flutter em diretório de trabalho separado do projeto.
- Verificação sintática e formatação dos arquivos Dart por `@wasm-fmt/dart_fmt` 0.4.0, port do formatador Dart para WebAssembly. Os arquivos passaram após correção de um fechamento de parênteses na tela de conflitos.
- Revisão de regras de centavos, competência, pagamento único derivado, transações, persistência de outbox, restauração e conflitos.
- Geração dos runners Android/Windows a partir dos templates oficiais; configuração de rede Android, armazenamento seguro, tema de abertura e assinatura release.

## Não executado com sucesso

O SDK baixado reportou Dart 3.13.5. Ao executar comandos de dependências, o ambiente retornou:

```text
Exception: type 'Null' is not a subtype of type 'String'
_Platform.resolvedExecutable
```

Executar um script mínimo diretamente também falhou:

```text
Failed to canonicalize path ... OS error: '(null)' (5).
```

A permissão adicional de leitura do diretório pai não resolveu o acesso. Um SDK Dart 3.10.8 também falhou ao resolver o caminho do mesmo script. Não foi possível completar `flutter pub get`, executar o analisador semântico ou iniciar os testes neste ambiente. Visual Studio C++ e Android SDK também não foram encontrados nos locais padrão verificados.

Portanto, **não há alegação de testes aprovados, build bem-sucedido, inspeção visual em execução ou sincronização ponta a ponta aprovada**. Não foram gerados APK, EXE ou captura de uma execução real. A validação sintática não detecta incompatibilidades de tipos/pacotes ou falhas de plugins em execução.

## Casos automatizados fornecidos para execução

- Finanças mensais sem carregar saldo anterior e manutenção de dívidas na virada do mês.
- Três meses acumulados, pagamento parcial, recebimento em competência diferente.
- Jornada de 4h30 a R$25/h, tarifa histórica, intervalos, meia-noite e arredondamento.
- Mesclagem offline, repetição idempotente, ordem de operações e exclusões.
- Edição/cancelamento de pagamento e independência de clientes.
- Distribuição FIFO por vários meses, excedentes e descontos sem receita.
- Rejeição atômica de exclusão de serviço já pago.
- Conflitos da mesma entidade, seleção manual e pagamentos concorrentes excessivos.
- Backup, checksum, duplicações, restauração e reabertura de banco persistente.
- CSV compatível com Excel e proteção de campos contra fórmulas.
- Filtros semanais e validação de datas.
- Transporte Drive com cliente HTTP controlado, incluindo falha após criação remota sem confirmação.
- Formulário de despesa e navegação em tamanhos de celular e desktop.

## Verificação necessária nos dispositivos

1. Execute `scripts/verificar.ps1` e corrija eventuais erros antes de distribuir binários.
2. Compile Windows e Android; teste salvar, fechar e reabrir sem internet.
3. Com dados de teste, repita o exemplo de JP (abril 2000, maio 1000, junho 2000; pagamento de 1000 em julho aplicado a abril).
4. Configure OAuth e conecte a mesma conta/projeto nos dois dispositivos.
5. Crie registros diferentes offline em cada dispositivo; sincronize ambos e sincronize novamente o primeiro.
6. Edite a mesma entidade nos dois dispositivos offline, revise o conflito e confirme que a resolução converge.
7. Registre pagamentos concorrentes que excedam a dívida, confirme o aviso e corrija o registro indevido.
8. Exporte/restaure o backup em outra instalação e confira valores, exclusões e pagamentos únicos.
9. Teste o retorno do navegador OAuth no Windows, expiração/reconexão, interrupção de rede e certificado release Android.

Somente após essa validação a versão deve ser considerada pronta para uso diário com os dados financeiros reais.
