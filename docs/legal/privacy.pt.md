# Recap — Política de privacidade

_Última atualização: 17 de outubro de 2026_

O Recap é uma aplicação de cartões para aprender línguas (inglês americano, português
europeu e italiano) com séries e aulas. É feito
por uma pessoa e não tem publicidade, análise nem rastreio. A conta é opcional.

## Responsável pelo tratamento

O responsável pelo tratamento dos dados pessoais aqui descritos é **CONTROLLER_NAME**,
CONTROLLER_ADDRESS, Portugal. Contacto: **CONTACT_EMAIL**.

## O que fica no telemóvel

Tudo o que a aplicação guarda fica apenas no teu dispositivo, e o criador não tem
acesso a isso:

- palavras, cartões, histórico de revisões e progresso;
- recontos e as respetivas análises;
- objetivos, recompensas e definições;
- o nome do perfil e a foto do avatar;
- chaves da API e a ligação à nuvem (no Keychain do iOS).

As fotos e os PDF das aulas são lidos no telemóvel (Vision da Apple) e não são enviados;
só segue o texto que vês no campo e podes corrigir.

As gravações de voz de pronúncia e recontos não são guardadas: só se usa o texto
reconhecido. O reconhecimento corre no telemóvel quando o iOS o permite; caso contrário,
o áudio é processado pelo serviço da Apple, segundo a
[política de privacidade da Apple](https://www.apple.com/legal/privacy/).

## O que sai do telemóvel — e só quando pedes

| Serviço | Quando | O que é enviado |
|---|---|---|
| **Anthropic (API do Claude)**, com a tua chave | Pedes um baralho ou uma análise de reconto, depois de autorizares | O texto do pedido, legendas anexadas, o texto do reconto e a lista de palavras que já tens. Vai do telemóvel diretamente para a Anthropic, na **tua** conta Anthropic; o criador não o recebe. Ver a [política da Anthropic](https://www.anthropic.com/legal/privacy). |
| **Servidor Recap** (só com Recap Plus ou código promocional) | Pedes palavras ou conversas com o Monchik sobre um episódio | Um número aleatório do dispositivo, o número da série/temporada/episódio, o idioma e o nível, as palavras que já tens, legendas anexadas e as falas da conversa. O servidor envia o texto à Anthropic e **não** o guarda. |
| **Servidor Recap: aulas** (só com Recap Plus ou código promocional) | Crias cartões de uma aula ou conversas com o Monchik sobre ela | O texto da aula, o título, as palavras que já tens, o idioma e o nível; na conversa — o título e as palavras da aula, o que contaste e as falas. O servidor envia o texto à Anthropic e **não** o guarda. Não coloques na aula dados pessoais de outras pessoas. |
| **Servidor Recap: Monchik Help** | Fazes uma pergunta ao assistente | O texto da pergunta e o idioma. O servidor envia-o à Anthropic e não o guarda. |
| **Servidor Recap: pedido de suporte** | Envias um pedido | O tema, o texto, o e-mail (se o indicares) e, se não o desligares, o diagnóstico: versões da app e do iOS, modelo do dispositivo, idiomas, número de cartões. Palavras e progresso não seguem. |
| **Apple** (só se iniciares sessão) | Tocas em «Iniciar sessão com a Apple» | A Apple confirma ao servidor Recap quem és. Pedimos apenas o nome, que fica no telemóvel. Nunca pedimos o e-mail. |
| **Servidor Recap: cópia na nuvem** (opcional) | Uma vez por dia, só se ligaste a «Cópia na nuvem» | Uma cópia comprimida da base de dados de estudo: baralhos, palavras, progresso. Cifrada no servidor. |
| **Apple (catálogo de filmes iTunes)** | Procuras um filme ou crias um baralho para ele | O título do filme que procuras; o servidor Recap pede à Apple os dados do filme escolhido pelo número. |
| **TVmaze** | Procuras uma série, crias um baralho para ela ou abres os baralhos prontos | O nome da série, a temporada e o episódio — para encontrar o cartaz e o título do episódio. Nos baralhos prontos, só o nome da série do catálogo. |

Nada é vendido nem partilhado para publicidade.

## O que o servidor Recap guarda, porquê e durante quanto tempo

O servidor só é usado por quem tem Recap Plus, um código promocional ou conta. Nunca
recebe o teu nome, e-mail ou foto.

| Dados | Porquê | Fundamento (RGPD) | Conservação |
|---|---|---|---|
| Pedidos de suporte: tema, texto, e-mail (opcional), diagnóstico, resposta | Responder-te e ver o que avaria mais | Contrato — art. 6.º, n.º 1, al. b); interesse legítimo — al. f) | Um ano após a última resposta; apagados com os dados ou a conta |
| Número aleatório do dispositivo e hash do seu token de acesso | Reconhecer o teu telemóvel | Contrato — art. 6.º, n.º 1, al. b) | Até apagares os dados, ou 12 meses após o último contacto do telemóvel com o servidor |
| Conta: HMAC do identificador de utilizador Apple | Encontrar a conta no próximo início de sessão | Contrato — art. 6.º, n.º 1, al. b) | Até apagares a conta, ou 12 meses após o último início de sessão se nenhum telemóvel estiver ligado |
| Conta: token de sessão da Apple, cifrado | Apenas para revogar o início de sessão com a Apple quando apagas a conta | Regras da plataforma Apple; contrato | Até apagares a conta |
| Número da transação da subscrição, produto, período, limite usado | Verificar a subscrição junto da Apple e aplicar o limite mensal | Contrato — art. 6.º, n.º 1, al. b) | Enquanto a subscrição estiver ligada a um dispositivo ou conta; caso contrário, 30 dias após terminar |
| Episódios para os quais obtiveste palavras | A conversa com o Monchik só é permitida sobre esses episódios | Contrato — art. 6.º, n.º 1, al. b) | Como o número do dispositivo |
| Número de tokens por pedido (sem conteúdo) | Ver custos e detetar abusos | Interesse legítimo — art. 6.º, n.º 1, al. f) | 90 dias |
| Cópia na nuvem: cópias comprimidas e cifradas da base de estudo, com data, número de palavras e nome do dispositivo | Restaurar num telemóvel novo | Contrato — art. 6.º, n.º 1, al. b) | As últimas 7 cópias; apagadas quando tocas em «Apagar todas as cópias», apagas os dados ou a conta, ou com o dispositivo ou a conta nos prazos acima |
| Contadores de pedidos por número do dispositivo ou HMAC do endereço IP | Evitar abusos (limites de frequência, tentativas de adivinhar códigos) | Interesse legítimo — art. 6.º, n.º 1, al. f) | Até ao fim da janela do contador (no máximo 24 horas) |

O texto dos pedidos, das aulas, as legendas, os recontos, as perguntas ao assistente e
as falas da conversa nunca são guardados no servidor nem nos seus registos. Com cada
pedido o servidor vê a versão da aplicação — para pedir que atualizes, se estiver desatualizada. A cópia na nuvem é a única exceção, e só
se a ligaste.

## Quem trata os dados por nossa conta

- **Cloudflare, Inc.** aloja o servidor Recap, a sua base de dados e as cópias na nuvem
  (D1 e R2), e encaminha ao responsável os e-mails dos pedidos de suporte.
- **Anthropic, PBC** fornece o modelo Claude, que gera as palavras e as respostas do
  Monchik. Segundo os termos comerciais da Anthropic, os dados da API não são usados
  para treinar modelos e são apagados após um período limitado (atualmente até 30 dias).
- **Apple** vende a subscrição, trata do pagamento, reembolsos e IVA, e confirma ao
  servidor a subscrição e o início de sessão. Para as compras e o Apple ID, a Apple é
  um responsável pelo tratamento independente.

A Cloudflare e a Anthropic estão sediadas nos Estados Unidos. As transferências estão
protegidas pelas Cláusulas Contratuais-Tipo da Comissão Europeia nos respetivos acordos
de tratamento de dados e, quando a empresa está certificada, pelo Quadro de Privacidade
de Dados UE-EUA.

## Os teus direitos

Tens direito de acesso, retificação, apagamento, limitação e portabilidade dos teus
dados, e de oposição ao tratamento baseado em interesse legítimo.

- **Ver e descarregar:** Perfil → Os meus dados no servidor mostra tudo o que o
  servidor guarda sobre o teu telemóvel e permite guardá-lo num ficheiro.
- **Apagar a conta:** Perfil → Apagar a conta. A conta é apagada e o início de sessão
  com a Apple é revogado.
- **Apagar tudo:** Perfil → Privacidade e apagar dados → **Apagar todos os dados**
  apaga tudo no telemóvel, a conta e o registo do dispositivo no servidor e, se
  escolheres, as cópias na nuvem no servidor Recap. Apagar a aplicação também apaga os
  dados locais. A subscrição pertence ao Apple ID e cancela-se nas definições da Apple.
- **Qualquer outro pedido:** na aplicação, «Ajuda → Escrever ao suporte → Os meus dados»
  (o pedido recebe logo um número), ou escreve para CONTACT_EMAIL e indica o código de suporte
  do Perfil — sem contas por e-mail, é a única forma de encontrar o teu registo.

Respondemos no prazo de um mês. Podes também apresentar reclamação à Comissão Nacional
de Proteção de Dados, **CNPD** ([www.cnpd.pt](https://www.cnpd.pt)), ou à autoridade
do teu país.

## IA

As palavras, as análises de recontos e as respostas do Monchik são geradas por um
modelo de IA (Claude, da Anthropic) e podem conter erros. A aplicação pede autorização
antes do primeiro pedido à IA, e podes retirá-la no ecrã Privacidade. Não são tomadas
decisões automatizadas com efeitos jurídicos ou similarmente significativos.

## Crianças

A aplicação não se destina a menores de 13 anos e não recolhe conscientemente os
seus dados (incluindo ao abrigo da regra COPPA dos EUA). Quando a App Store indica
que o utilizador tem menos de 13 anos, a aplicação não abre. Em Portugal e na maior
parte da UE, os menores de 13 anos (ou da idade fixada pelo seu país) precisam de
autorização dos pais para usar serviços online que tratam dados pessoais. Se achas
que uma criança com menos de 13 anos nos enviou dados, escreve-nos e apagamo-los.

## Segurança

As ligações usam HTTPS. O servidor guarda tokens de acesso e códigos promocionais
apenas como hashes criptográficos, o identificador Apple e os endereços IP apenas como
HMAC, e o token de sessão da Apple apenas cifrado. Se ocorrer uma violação que afete os
teus dados, notificamos a CNPD no prazo de 72 horas e informamos-te quando a lei o exigir.

## Se vives nos Estados Unidos

As leis estaduais de privacidade — a CCPA/CPRA da Califórnia e as leis da Virgínia,
do Colorado, do Connecticut, do Texas e de outros estados — dão-te direitos sobre as
tuas informações pessoais. É assim que se aplicam ao Recap:

- **O que recolhemos:** identificadores (um número aleatório do dispositivo, um HMAC
  do identificador Apple); informação comercial (a transação e o período da
  subscrição); utilização limitada a contadores de pedidos e número de tokens; e o
  conteúdo que decides enviar (pedidos de suporte, cópias na nuvem). Vem de ti, do
  teu telemóvel e da Apple. As finalidades e os prazos estão nas tabelas acima.
- **Não vendemos nem partilhamos para publicidade.** Não vendemos informações
  pessoais, não as partilhamos para publicidade comportamental, não as usamos para
  publicidade dirigida nem para definição de perfis, e não o fizemos nos últimos
  12 meses. Não as divulgamos a terceiros para o marketing deles.
- **Dados sensíveis:** não recolhemos localização exata, documentos de identificação
  nem dados biométricos. A voz serve apenas para reconhecer a fala e não é guardada;
  não criamos impressões vocais.
- **Os teus direitos:** saber e aceder, apagar, corrigir e obter uma cópia dos teus
  dados — com as mesmas ferramentas indicadas acima. Respondemos no prazo de 45 dias
  e não te tratamos de forma diferente por exerceres os teus direitos. Para encontrar
  o teu registo pedimos o código de suporte do Perfil. Um representante autorizado
  pode agir por ti com a tua autorização assinada. Se recusarmos um pedido, responde
  à nossa resposta para recorrer; se o recurso for recusado, podes contactar o
  procurador-geral (attorney general) do teu estado.
- **Verificação de idade:** onde a lei estadual o exige (por exemplo, no Texas), a
  App Store indica à app o teu escalão etário — menos de 13, 13–15, 16–17 ou 18+,
  nunca a data de nascimento. Só o resultado da verificação é guardado, no
  telemóvel; não é enviado para o servidor. As compras de menores passam pelo
  consentimento parental da Apple.
- **Do Not Track:** a app não te segue noutras apps nem em sites, por isso estes
  sinais não alteram nada.

## Alterações

Se esta política mudar, a nova versão aparece aqui e na aplicação com nova data.
