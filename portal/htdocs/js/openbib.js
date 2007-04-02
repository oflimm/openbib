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

function insert_tag(event) {

  var this_element = "";
  
  if (!event)
    event = window.event;

  if (event.srcElement) {
    // Der Internet Explorer verwendet srcElement
    this_element = event.srcElement;
  }
  else if (event.target) {
    // Mozilla und Abkoemmlinge verwenden target
    this_element = event.target;
  }
  
  var tag  = this_element.childNodes[0].nodeValue;

  tag = tag.replace(/ /,"");
  
  var this_input = document.getElementById('inputfield');
  
  var tags = this_input.value.split(" ");
  
  if (tags[0] == "") {
    tags.splice(0,1);
  }
  
  var done = 0;
  var new_tags = new Array();
  
  for (var i = 0; i < tags.length; i++) {
    var this_tag = tags[i];
    if (tag == this_tag) {
      done = 1;
    }
    else {
      new_tags.push(this_tag);
    }
  }
      
  if (!done) {
    new_tags.push(tag) ;
  }
  
  var new_input = new_tags.join(" ");
  this_input.value = new_input;
  
  this_input.focus();
}
