function createInput() {
  var div = document.getElementById('attachSandbox');
  while (div.firstChild) div.removeChild(div.firstChild);
  var input = document.createElement('input');
      input.type = "text";
  div.appendChild(input);
}


function applyKeyboard() {
  var div = document.getElementById('attachSandbox');
  var input = div.getElementsByTagName('input');
  if (input.length) {
    VKI_attach(input[0]);
  } else alert('Create the input first!');
}