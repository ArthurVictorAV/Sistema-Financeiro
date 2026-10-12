# Arthur Victor — Finanças & Trabalho

Aplicativo pessoal Flutter para Android e Windows. Interface em português, tema preto/grafite e dourado, logo original anexada, SQLite local e sincronização por operações na pasta privada do Google Drive.

**Estado da entrega:** implementação em código-fonte, com testes automatizados incluídos. Não há APK ou executável compilado nesta entrega. A sintaxe dos arquivos Dart foi verificada com um parser/formatador; `flutter pub get`, `flutter analyze`, `flutter test` e builds não puderam ser concluídos neste ambiente. A autenticação e a sincronização com uma conta Google real precisam de configuração e validação nos dispositivos. Consulte `VALIDACAO.md` antes de usar dados importantes.

## O que está implementado

- Início com entradas, despesas e resultado apenas do período escolhido.
- Lançamentos com busca, filtros, categoria, cliente opcional, edição e exclusão confirmada.
- Clientes/patrões, começando por JP, com tarifa padrão e observações.
- Jornadas por entrada/saída ou duração direta, intervalos, meia-noite, prévia de valores e tarifa histórica.
- Extras e descontos por competência mensal.
- Dívidas mensais e acumuladas, pagamentos parciais, recebimentos e correções vinculados ao financeiro.
- Pagamento aplicado a um mês escolhido ou distribuído pelas dívidas antigas.
- Dia, semana, mês e ano; relatórios, evolução mensal, categorias e exportação CSV.
- Backup JSON com SHA-256, restauração por mesclagem e cópia automática anterior à restauração.
- Operações imutáveis, exclusões propagadas, detecção de conflitos e revisão manual.
- Google Drive API v3 real via HTTP; autenticação Android nativa e Windows por navegador/PKCE.
- Navegação inferior em telas menores que 850 px e lateral nas maiores.

A exportação PDF opcional não está implementada. Não há Firebase, servidor próprio, dados financeiros fictícios, assinatura ou tela simulando conexão bem-sucedida.

## 1. Preparar o computador

1. Instale o [Flutter estável](https://docs.flutter.dev/install) com Dart 3.10 ou superior. Para os projetos nativos fornecidos, prefira o Flutter estável atual: os templates Android usam Gradle 9.3.1, AGP 9.1.0 e Kotlin 2.4.0, obtidos do SDK estável consultado durante a implementação.
2. Adicione a pasta `flutter/bin` ao PATH e abra outro PowerShell.
3. Para Android, instale Android Studio, Android SDK, Command-line Tools e JDK 17. Use o SDK recomendado pelo `flutter doctor`. O aplicativo define Android mínimo 23.
4. Para Windows, instale Visual Studio com a carga **Desenvolvimento para desktop com C++**, SDK Windows e CMake. VS Code sozinho não contém esse compilador. Siga o [guia oficial de Windows](https://docs.flutter.dev/platform-integration/windows/setup).
5. Ative o Modo de Desenvolvedor do Windows caso o Flutter peça suporte a links simbólicos para plugins.

Na pasta deste projeto:

```powershell
flutter doctor -v
flutter doctor --android-licenses
flutter config --enable-windows-desktop
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
```

Também é possível executar `./scripts/verificar.ps1` em um PowerShell com execução de scripts locais permitida. Ele interrompe o processo se algum comando falhar.

O primeiro `flutter pub get` produzirá `pubspec.lock`; guarde esse arquivo no controle de versão depois de validar a resolução. Não há lockfile inventado nesta entrega. As dependências transitivas ainda não foram resolvidas neste ambiente.

## 2. Executar

No Windows:

```powershell
flutter run -d windows
```

No Android, ative a depuração USB, conecte o celular e autorize o computador:

```powershell
flutter devices
flutter run -d ID_DO_CELULAR
```

O aplicativo funciona sem configurar Google. Abra **Trabalho → JP → editar**, informe sua tarifa e registre as jornadas. Nenhum saldo de exemplo é inserido.

O banco fica no diretório de suporte do aplicativo retornado por `path_provider`, com o nome `arthur_victor.sqlite`. No Android esse diretório pertence ao aplicativo; no Windows, fica no perfil do usuário. Não coloque o banco em uma pasta de sincronização de arquivos.

## 3. Configurar Google Cloud

Crie um único projeto no [Google Cloud Console](https://console.cloud.google.com/). Use esse mesmo projeto para todos os clientes OAuth dos dois dispositivos.

1. Em **APIs e serviços → Biblioteca**, habilite **Google Drive API**.
2. Configure a marca/tela de consentimento no Google Auth Platform, com nome do aplicativo, e-mail de suporte e contato.
3. Para uma conta pessoal, escolha público externo e adicione sua própria conta como usuário de teste enquanto o projeto estiver em testes.
4. Cadastre o escopo `https://www.googleapis.com/auth/drive.appdata`. O Windows também solicita `openid email` para vincular o banco à conta correta.
5. Crie as credenciais descritas a seguir.

Não é necessário publicar o aplicativo na Play Store. A Drive API usa a conta e as cotas do Google; não há backend pago contratado pelo projeto. A pasta `appDataFolder` não aparece como uma pasta comum na interface do Drive. Veja a [documentação oficial de dados privados de aplicativos](https://developers.google.com/workspace/drive/api/guides/appdata).

### Android

Crie um cliente OAuth do tipo **Android**:

- Pacote: `com.arthurvictor.controle`.
- Certificado SHA-1: o certificado com que o APK foi assinado.

Depois da primeira preparação do Flutter/Gradle, obtenha os certificados locais com:

```powershell
cd android
./gradlew.bat signingReport
cd ..
```

Cadastre as impressões digitais de debug e release como clientes Android correspondentes. Trocar o certificado sem atualizar as credenciais impede o login.

Crie também um cliente OAuth do tipo **Aplicativo Web** no mesmo projeto. O SDK oficial Android utiliza seu **ID** como `serverClientId`; o fluxo de autorização continua sendo o SDK Android com validação de pacote/certificado. Não configure segredo Web no aplicativo. Não é necessário Firebase nem `google-services.json` neste projeto.

No aplicativo, abra **Configurações → Configurar credenciais OAuth → ID Web (serverClientId do Android)**. Salve e reinicie antes de conectar. Essa configuração segue o [README oficial do plugin Android](https://pub.dev/packages/google_sign_in_android).

### Windows

Crie um cliente OAuth do tipo **Aplicativo para computador / Desktop app** no mesmo projeto. Informe no aplicativo seu ID e o valor `client_secret` dessa credencial Desktop.

Esse valor é próprio de um cliente instalado/público: não equivale a um segredo confidencial de servidor e não substitui PKCE. Ele não está embutido no código e é armazenado pelo cofre do sistema. Nunca coloque um segredo de cliente Web nesse campo. O fluxo usa navegador externo, `state` aleatório, PKCE S256 e callback em `127.0.0.1` com porta efêmera; não usa navegador embutido nem callback loopback no Android. Veja o [fluxo oficial para aplicativos instalados](https://developers.google.com/identity/protocols/oauth2/native-app).

O navegador retorna ao aplicativo depois do consentimento. Tokens de atualização ficam no armazenamento seguro do sistema; senhas Google nunca são solicitadas pelo aplicativo.

### Consentimento em modo de testes

Em projetos externos mantidos como **Testing**, autorizações com escopos além dos básicos de identidade podem expirar em sete dias. Será necessário reconectar. Para uso contínuo, revise os requisitos aplicáveis à publicação da tela de consentimento no Google Cloud; isso é diferente de publicar o APK em uma loja. Revogação pelo usuário e outras políticas também podem invalidar tokens. Consulte a seção de expiração na [documentação OAuth oficial](https://developers.google.com/identity/protocols/oauth2).

## 4. Conectar os dois dispositivos

1. Configure as credenciais adequadas em cada instalação.
2. No primeiro dispositivo, clique em **Conectar Google** e autorize sua conta.
3. Aguarde **Sincronizado** e confira a data exibida.
4. No segundo dispositivo, conecte exatamente a mesma conta, usando clientes OAuth do mesmo projeto.
5. Sincronize novamente no primeiro para buscar alterações que o segundo tenha enviado depois da leitura inicial.

O banco fica vinculado à primeira conta usada para evitar mesclar finanças de contas diferentes. **Desconectar** remove o login local; não apaga dados, não remove arquivos do Drive e não altera esse vínculo. Para revogar a permissão no Google, use a página de permissões da própria conta Google.

O aplicativo tenta sincronizar ao abrir, retomar e três segundos depois de mudanças. Falhas de conexão recebem uma nova tentativa enquanto ele permanece aberto; erros de autorização ou de API aparecem na tela para reconexão ou tentativa manual. Não há garantia de execução quando o aplicativo está fechado.

## 5. Regras financeiras

Valores são inteiros em centavos e durações são inteiros em minutos. A remuneração de cada jornada é arredondada para o centavo mais próximo, com meio centavo arredondado para cima: `(minutos × tarifaEmCentavos + 30) ~/ 60`.

- 08:00–12:30, sem intervalo, a R$ 25/h: 270 minutos e R$ 112,50.
- A saída menor que a entrada significa dia seguinte. Horários iguais são rejeitados; para 24 horas, use duração direta.
- Jornadas noturnas pertencem à data de início. A tarifa é copiada para a jornada e não muda se a tarifa padrão do cliente mudar.
- Uma movimentação pessoal usa somente a data financeira, sem horário.
- O saldo pessoal é entradas recebidas menos despesas pagas dentro do intervalo selecionado. Não carrega o saldo de meses anteriores.
- Serviços e extras aumentam dívida, descontos a reduzem e não geram receita.
- A competência do ajuste é explícita e pode diferir da data de registro do fato.
- Pagamentos contêm suas alocações por competência e geram uma única entrada financeira **derivada**, com o mesmo identificador. Não existe cópia separada editável que possa ficar desatualizada.
- Corrigir/cancelar o pagamento altera o recebimento e a dívida juntos. Editar apenas data/observação preserva a distribuição existente por padrão.
- Escolher um mês restringe o pagamento à dívida desse mês; escolher as dívidas antigas distribui o valor entre competências, da mais antiga à mais recente.
- Pagamentos/descontos locais que deixariam uma competência negativa são rejeitados. Não há modalidade de adiantamento nesta versão.
- A semana começa na segunda-feira. Todos os filtros usam datas civis locais, sem deslocamento UTC de competência.

## 6. Sincronização e conflitos

O SQLite armazena revisões imutáveis por entidade em `operations`, com UUID, UUID do dispositivo, contador lógico de versão, versões anteriores conhecidas e conteúdo. A tabela `settings` contém preferências locais, vínculo da conta e estado de sincronização. `PRAGMA user_version` controla a versão do esquema, atualmente 1; bancos de versão superior são recusados sem substituição.

As entidades de clientes, categorias, jornadas, ajustes e pagamentos são projeções dessas operações. UUIDs únicos e validação do histórico são aplicados antes da transação SQLite. O cadastro inicial JP usa UUIDs determinísticos para não aparecer duplicado ao juntar duas instalações vazias.

Cada operação pendente gera um arquivo `av-op-UUID.json` em `appDataFolder`. Arquivos existentes não são sobrescritos. O recebimento de um lote valida todas as versões anteriores antes de persistir; uma falha não descarta o histórico local. O envio só marca uma operação como confirmada depois da resposta de sucesso.

Uma falha depois de o Drive criar um arquivo, mas antes de confirmar a resposta, pode gerar dois arquivos de transporte iguais. O UUID evita que isso gere duas operações ou dois recebimentos no banco. Sincronizar repetidamente é idempotente para o mesmo conjunto de operações.

Edições concorrentes da mesma entidade preservam todas as versões. Um desempate estável por contador lógico e UUID produz uma visão provisória igual nos dois dispositivos. O aviso aparece em todas as áreas; **Configurações → Revisar alterações** permite escolher a versão correta. A escolha cria uma nova revisão que referencia todas as versões concorrentes. Exclusões também são revisões, portanto um backup antigo não ressuscita automaticamente um registro excluído.

Pagamentos independentes feitos offline podem, juntos, exceder uma dívida. Não é possível impedir isso nos dois dispositivos desconectados sem coordenação online. O aplicativo preserva ambos, mostra a inconsistência e marca os totais como provisórios. Corrija ou exclua o registro incorreto na página do cliente; não oculta nem descarta silenciosamente dinheiro recebido. Resolva conflitos antes de novos pagamentos. Testes cobrem esse caso no código, mas ainda precisam ser executados.

Não há compactação automática do histórico ou paginação da interface nesta primeira versão. O Drive é listado com paginação e somente operações desconhecidas são baixadas. O custo de leitura local e de listagem cresce com o histórico; a solução foi dimensionada conceitualmente para uso pessoal, sem benchmark de grande volume.

## 7. Backup e restauração

Em **Configurações → Exportar backup**, escolha onde salvar o JSON. O arquivo inclui o histórico e as exclusões, mas não inclui tokens Google, credenciais OAuth ou identidade do dispositivo.

Ao restaurar:

1. O formato, a versão, o SHA-256, as entidades e o histórico de versões são validados.
2. O aplicativo solicita confirmação para mesclar.
3. Salva uma cópia `antes-restauracao-DATA.json` no diretório de suporte.
4. Mescla pelo UUID e mantém operações locais mais novas ou concorrentes.
5. Novas operações restauradas ficam pendentes para envio ao Drive.

Restauração é recuperação por mesclagem, não uma reversão destrutiva para uma fotografia antiga. Para recuperar uma versão antiga de um registro editado, use o histórico/conflito correspondente ou edite o registro atual; tombstones recentes continuam válidos. O backup não é criptografado: guarde-o em local adequado. O checksum detecta corrupção acidental e não constitui assinatura contra adulteração intencional.

## 8. Gerar APK

Para instalar e validar uma versão de teste:

```powershell
flutter build apk --debug
```

O resultado será `build/app/outputs/flutter-apk/app-debug.apk`. Autorize a instalação dessa origem no Android e abra o APK. Esse arquivo não acompanha a presente entrega porque o build não foi executado.

Para sua versão permanente, gere e guarde uma chave de assinatura:

```powershell
keytool -genkeypair -v -keystore C:/caminho/seguro/arthur-victor.jks -alias arthur-victor -keyalg RSA -keysize 2048 -validity 10000
```

Copie `android/key.properties.example` para `android/key.properties`, preencha localmente os valores e o caminho. Não envie a chave nem esse arquivo para um repositório. Cadastre o SHA-1 da chave de release no cliente OAuth Android.

```powershell
flutter build apk --release
```

O APK será `build/app/outputs/flutter-apk/app-release.apk`. Builds release sem arquivo de chave são recusados, para não publicar acidentalmente uma versão assinada com a chave de debug. Trocar debug por release pode exigir desinstalação pela mudança da assinatura; exporte o backup antes dessa transição.

## 9. Gerar versão Windows

```powershell
flutter build windows --release
```

Distribua **toda** a pasta `build/windows/x64/runner/Release`, incluindo o executável, DLLs e diretório `data`. Copiar apenas o `.exe` não é suficiente. Pode ser necessário o Microsoft Visual C++ Redistributable compatível no computador de destino. Esta entrega fornece o runner Windows, mas não um instalador ou binário já validado.

O ícone nativo do runner Windows permanece genérico nesta versão; a marca original aparece na abertura Flutter e na interface. O arquivo completo da identidade está preservado em `assets/brand.png`; o widget exibe o símbolo principal por um recorte de viewport sem alterar seus pixels ou sua cor prata.

## 10. Atualizar sem perder dados

Exporte um backup antes de atualizar. No Android, preserve `applicationId` e a mesma chave de assinatura e aumente o número de build no `pubspec.yaml`. Instale sobre a versão anterior. Não desinstale nem limpe o armazenamento para uma atualização normal.

No Windows, feche o programa e substitua a pasta de distribuição, mantendo o diretório de suporte no perfil do usuário. Não mude o identificador do aplicativo ou a política de localização dos dados sem uma migração explícita.

Futuras mudanças de esquema devem incrementar `user_version`, executar migrações em transação, manter compatibilidade de leitura das operações e ser testadas sobre um banco de versão anterior. Não edite arquivos de operações já enviados ao Drive. Atualize as duas instalações quando houver mudança de formato que exija uma versão mínima.

## Organização do código

| Arquivo | Responsabilidade |
|---|---|
| `lib/domain.dart` | Centavos, minutos, datas, validação, projeção de entidades e dívidas |
| `lib/store.dart` | SQLite, transações, revisões, outbox, backup e CSV |
| `lib/sync.dart` | OAuth por plataforma e transporte de operações no Drive |
| `lib/ui/identity.dart` | Paleta, tema e logo original |
| `lib/ui/record_form.dart` | Formulários, prévias, edição e exclusão |
| `lib/main.dart` | Abertura, navegação, telas, relatórios e configurações |
| `test/ledger_test.dart` | Regras financeiras, persistência, conflitos e recuperação |
| `test/sync_test.dart` | Transporte HTTP controlado, sincronização e repetição após falha |
| `test/widget_test.dart` | Navegação e registro de despesa em celular e desktop |

O workflow `.github/workflows/validate.yml` pode executar análise, testes e builds ao colocar o projeto na raiz de um repositório GitHub. Ele não foi executado nem publicado nesta entrega. O transporte controlado dos testes não substitui um ensaio com a conta Google real.

## Compatibilidade consultada

As plataformas declaradas pelos mantenedores foram verificadas antes da escolha. Isso verifica a declaração de suporte, não comprova execução neste aplicativo:

- [sqlite3 3.x](https://pub.dev/packages/sqlite3): Android/Windows, biblioteca SQLite empacotada pelos hooks nativos; dispensa código gerado Drift.
- [google_sign_in 7.2](https://pub.dev/packages/google_sign_in): Android; não oferece Windows, por isso existe um fluxo Desktop separado.
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage): cofre nativo em Android e Windows.
- [file_picker 10.3.10](https://pub.dev/packages/file_picker/versions/10.3.10): escolha e salvamento de arquivo nas duas plataformas. Foi fixada a linha de API 10.x deliberadamente.
- [path_provider](https://pub.dev/packages/path_provider) e [url_launcher](https://pub.dev/packages/url_launcher): diretórios locais e navegador externo nas plataformas de destino.

Os runners partem dos templates oficiais do Flutter. A licença correspondente está em `NOTICE_FLUTTER.txt`. A logo fornecida é a identidade de Arthur Victor.
