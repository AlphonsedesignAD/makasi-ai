module.exports = async (req, res) => {
  const key1 = process.env.CODECRAFT_KEY_1 || '';
  const apiUrl = process.env.CODECRAFT_API_URL || '';
  const model = process.env.CODECRAFT_MODEL || '';
  const supaUrl = process.env.SUPABASE_URL || '';
  const supaKey = process.env.SUPABASE_ANON_KEY || '';

  const cleanKey = key1.replace(/^["']|["']$/g, '').trim();
  const cleanApi = (apiUrl || 'https://codecraftapi.com/v1/chat/completions').replace(/^["']|["']$/g, '').trim();
  const cleanModel = (model || 'claude-sonnet-5').replace(/^["']|["']$/g, '').trim();

  let testResult = null;
  try {
    const testReq = await fetch(cleanApi, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + cleanKey
      },
      body: JSON.stringify({
        model: cleanModel,
        messages: [{ role: 'user', content: 'test' }]
      })
    });
    const status = testReq.status;
    const bodyText = await testReq.text();
    testResult = { status, bodyPreview: bodyText.slice(0, 300) };
  } catch (err) {
    testResult = { error: err.message };
  }

  return res.status(200).json({
    env: {
      has_key_1: Boolean(key1),
      key_1_length: key1.length,
      key_1_preview: key1 ? `${key1.slice(0, 8)}...${key1.slice(-4)}` : null,
      key_1_has_quotes: key1.startsWith('"') || key1.startsWith("'"),
      api_url: apiUrl,
      model: model,
      has_supa_url: Boolean(supaUrl),
      has_supa_key: Boolean(supaKey)
    },
    codecraft_live_test: testResult
  });
};
