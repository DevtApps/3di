// Registros consecutivos distribuídos nas duas dimensões, sem limitar um registro por linha.
export function packDataTexture(values, recordWidth, maxSize) {
  const texels = values.length / 4;
  if (!Number.isInteger(texels) || !Number.isInteger(maxSize) || maxSize < 1 || texels > maxSize * maxSize) {
    throw new Error(`Os dados da cena excedem a capacidade de textura desta GPU (${maxSize} × ${maxSize}); divida a cena entre arquivos ou use uma GPU com mais capacidade.`);
  }
  const width = Math.min(maxSize, Math.max(recordWidth, Math.ceil(Math.sqrt(texels))));
  const height = Math.max(1, Math.ceil(texels / width));
  const pixels = new Float32Array(width * height * 4);
  pixels.set(values);
  return { width, height, pixels };
}
