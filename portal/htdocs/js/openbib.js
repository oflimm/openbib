function expandContentVis(content,img){
  var data = eval('document.getElementById("' + content +'")');
  if (data.style.visibility=="visible" || data.style.visibility=="" ){
    data.style.visibility="hidden";
    img.src='/images/openbib/expand.png';
  }
  else{
    data.style.visibility="";
    img.src='/images/openbib/collapse.png';
  }
}

function expandContent(content,img){
  var data = eval('document.getElementById("' + content +'")');
  if (data.style.display=="block" || data.style.display=="" ){
    data.style.display="none";
    img.src='/images/openbib/expand.png';
  }
  else{
    data.style.display="";
    img.src='/images/openbib/collapse.png';
  }
}
