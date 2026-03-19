bool validarDniNie(String dni) {
  final dniUpper = dni.toUpperCase().trim();
  final dniRegex = RegExp(r'^[0-9]{8}[A-Z]$');
  final nieRegex = RegExp(r'^[XYZ][0-9]{7}[A-Z]$');

  if (!dniRegex.hasMatch(dniUpper) && !nieRegex.hasMatch(dniUpper)) {
    return false;
  }

  const letras = 'TRWAGMYFPDXBNJZSQVHLCKE';
  var numStr = dniUpper;

  if (dniUpper.startsWith('X')) {
    numStr = '0${dniUpper.substring(1)}';
  } else if (dniUpper.startsWith('Y')) {
    numStr = '1${dniUpper.substring(1)}';
  } else if (dniUpper.startsWith('Z')) {
    numStr = '2${dniUpper.substring(1)}';
  }

  final numero = int.tryParse(numStr.substring(0, numStr.length - 1));
  if (numero == null) return false;

  final letraEsperada = letras[numero % 23];
  final letraIntroducida = dniUpper[dniUpper.length - 1];

  return letraEsperada == letraIntroducida;
}
